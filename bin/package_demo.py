#!/usr/bin/env python3
"""Build and verify the portable LaunchPulse delivery archive."""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import PurePosixPath
import stat
import subprocess
import sys
import zipfile


MANIFEST_NAME = ".delivery-manifest.json"
MANIFEST_VERSION = 1
HASH_CHUNK_SIZE = 1024 * 1024
SHA256_LENGTH = 64


class PackageError(Exception):
    """A safe, user-facing package validation failure."""


def normalized_path(name: object) -> PurePosixPath | None:
    if not isinstance(name, str) or not name or "\\" in name or name.endswith("/"):
        return None
    path = PurePosixPath(name)
    if path.is_absolute() or path.as_posix() != name:
        return None
    if any(part in ("", ".", "..") for part in path.parts):
        return None
    return path


def blocked_path(path: PurePosixPath) -> bool:
    lowered = tuple(part.lower() for part in path.parts)
    basename = lowered[-1]

    if any(part == ".git" for part in lowered):
        return True
    if lowered[0] in (
        "__macosx",
        ".kamal",
        "tmp",
        "log",
        "storage",
        "output",
        ".playwright-cli",
        ".bundle",
        "coverage",
    ):
        return True
    if basename == ".ds_store":
        return True
    if lowered[:2] in (("docs", "superpowers"), ("vendor", "bundle"), ("public", "assets")):
        return True
    if lowered[:3] == ("app", "assets", "builds"):
        return True
    if basename.startswith(".env"):
        return True
    if basename.endswith((".pem", ".p12", ".pfx")):
        return True
    return lowered[0] == "config" and basename.endswith(".key")


def validate_source_path(relative: object) -> PurePosixPath:
    path = normalized_path(relative)
    if path is None:
        raise PackageError("Unsafe package path")
    if path.as_posix() == MANIFEST_NAME:
        raise PackageError(f"Reserved package path: {MANIFEST_NAME}")
    if blocked_path(path):
        raise PackageError(f"Blocked package path: {path.as_posix()}")
    if path.parts[0].lower() == "readme" and any(ord(character) > 127 for character in path.as_posix()):
        raise PackageError(f"Non-ASCII readme path: {path.as_posix()}")
    return path


def root_descriptor(root: str) -> int:
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    directory = getattr(os, "O_DIRECTORY", 0)
    if not nofollow or not directory:
        raise PackageError("Secure descriptor traversal is unavailable")
    try:
        return os.open(root, os.O_RDONLY | directory | nofollow)
    except OSError as error:
        raise PackageError("Project root is unavailable") from error


def open_regular(root_fd: int, path: PurePosixPath) -> tuple[int, os.stat_result]:
    nofollow = os.O_NOFOLLOW
    directory = os.O_DIRECTORY
    directory_fd = os.dup(root_fd)
    try:
        for component in path.parts[:-1]:
            child_fd = os.open(component, os.O_RDONLY | directory | nofollow, dir_fd=directory_fd)
            os.close(directory_fd)
            directory_fd = child_fd
        file_fd = os.open(path.parts[-1], os.O_RDONLY | nofollow, dir_fd=directory_fd)
        try:
            metadata = os.fstat(file_fd)
            if not stat.S_ISREG(metadata.st_mode):
                raise OSError("entry is not a regular file")
        except BaseException:
            os.close(file_fd)
            raise
        return file_fd, metadata
    finally:
        os.close(directory_fd)


def read_regular(root_fd: int, path: PurePosixPath) -> bytes:
    try:
        file_fd, _metadata = open_regular(root_fd, path)
    except OSError as error:
        raise PackageError(f"Unsafe package path: {path.as_posix()}") from error
    with os.fdopen(file_fd, "rb") as source:
        return source.read()


def parse_manifest(data: bytes) -> list[dict[str, str]]:
    try:
        document = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PackageError("Invalid delivery manifest") from error
    if not isinstance(document, dict):
        raise PackageError("Invalid delivery manifest")
    version = document.get("version")
    files = document.get("files")
    if isinstance(version, bool) or not isinstance(version, int) or version != MANIFEST_VERSION:
        raise PackageError("Invalid delivery manifest version")
    if not isinstance(files, list):
        raise PackageError("Invalid delivery manifest files")

    parsed: list[dict[str, str]] = []
    seen: set[str] = set()
    for entry in files:
        if not isinstance(entry, dict):
            raise PackageError("Invalid delivery manifest entry")
        relative = entry.get("path")
        digest = entry.get("sha256")
        path = validate_source_path(relative)
        canonical = path.as_posix()
        if canonical in seen:
            raise PackageError(f"Duplicate manifest path: {canonical}")
        seen.add(canonical)
        if not isinstance(digest, str) or len(digest) != SHA256_LENGTH:
            raise PackageError(f"Invalid manifest hash: {canonical}")
        if any(character not in "0123456789abcdef" for character in digest):
            raise PackageError(f"Invalid manifest hash: {canonical}")
        parsed.append({"path": canonical, "sha256": digest})
    return parsed


def git_source_paths(root: str) -> list[dict[str, str | None]] | None:
    top_level = subprocess.run(
        ["git", "-C", root, "rev-parse", "--show-toplevel"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if top_level.returncode != 0:
        return None
    try:
        discovered_root = os.path.realpath(os.fsdecode(top_level.stdout).strip())
    except UnicodeDecodeError as error:
        raise PackageError("Git project root is invalid") from error
    if discovered_root != root:
        return None

    tracked = subprocess.run(
        ["git", "-C", root, "ls-files", "-z", "--cached"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if tracked.returncode != 0:
        raise PackageError("Git tracked-file manifest is unavailable")
    data = tracked.stdout
    if data and not data.endswith(b"\0"):
        raise PackageError("Git tracked-file manifest is invalid")
    raw_names = data.split(b"\0")[:-1] if data else []

    files: list[dict[str, str | None]] = []
    seen: set[str] = set()
    for raw_name in raw_names:
        relative = os.fsdecode(raw_name)
        path = validate_source_path(relative)
        canonical = path.as_posix()
        if canonical in seen:
            raise PackageError(f"Duplicate tracked path: {canonical}")
        seen.add(canonical)
        files.append({"path": canonical, "sha256": None})
    return files


def non_git_source_paths(root_fd: int) -> list[dict[str, str | None]]:
    manifest_path = PurePosixPath(MANIFEST_NAME)
    try:
        data = read_regular(root_fd, manifest_path)
    except PackageError as error:
        raise PackageError("Root delivery manifest is unavailable") from error
    return [dict(entry) for entry in parse_manifest(data)]


def zip_timestamp(metadata: os.stat_result) -> tuple[int, int, int, int, int, int]:
    modified = datetime.datetime.fromtimestamp(metadata.st_mtime)
    modified = max(modified, datetime.datetime(1980, 1, 1))
    return modified.timetuple()[:6]


def archive_file(
    archive: zipfile.ZipFile,
    root_fd: int,
    path: PurePosixPath,
    expected_hash: str | None,
) -> dict[str, str]:
    relative = path.as_posix()
    try:
        file_fd, metadata = open_regular(root_fd, path)
    except OSError as error:
        raise PackageError(f"Unsafe package path: {relative}") from error

    info = zipfile.ZipInfo(relative, zip_timestamp(metadata))
    info.create_system = 3
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = (metadata.st_mode & 0xFFFF) << 16
    digest = hashlib.sha256()
    with os.fdopen(file_fd, "rb") as source, archive.open(info, "w", force_zip64=True) as target:
        while chunk := source.read(HASH_CHUNK_SIZE):
            digest.update(chunk)
            target.write(chunk)
    actual_hash = digest.hexdigest()
    if expected_hash is not None and actual_hash != expected_hash:
        raise PackageError(f"Source hash mismatch: {relative}")
    return {"path": relative, "sha256": actual_hash}


def manifest_data(files: list[dict[str, str]]) -> bytes:
    document = {"version": MANIFEST_VERSION, "files": files}
    return (json.dumps(document, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def build_archive(root: str, output: str) -> None:
    root = os.path.realpath(root)
    root_fd = root_descriptor(root)
    try:
        sources = git_source_paths(root)
        if sources is None:
            sources = non_git_source_paths(root_fd)
        try:
            with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                packaged = []
                for source in sources:
                    path = validate_source_path(source["path"])
                    packaged.append(archive_file(archive, root_fd, path, source["sha256"]))
                archive.writestr(MANIFEST_NAME, manifest_data(packaged))
        except BaseException:
            try:
                os.unlink(output)
            except FileNotFoundError:
                pass
            raise
    finally:
        os.close(root_fd)


def verify_archive(archive_path: str) -> None:
    try:
        archive = zipfile.ZipFile(archive_path)
    except (OSError, zipfile.BadZipFile) as error:
        raise PackageError("Delivery archive is unreadable") from error

    with archive:
        entries = archive.infolist()
        manifest_entries = [entry for entry in entries if entry.filename == MANIFEST_NAME]
        if len(manifest_entries) != 1:
            raise PackageError("Delivery manifest must appear exactly once")

        by_name: dict[str, zipfile.ZipInfo] = {}
        for entry in entries:
            path = normalized_path(entry.filename)
            if path is None:
                raise PackageError("Unsafe package entry")
            canonical = path.as_posix()
            if canonical in by_name:
                raise PackageError(f"Duplicate package entry: {canonical}")
            by_name[canonical] = entry
            mode = (entry.external_attr >> 16) & 0xFFFF
            if stat.S_ISLNK(mode):
                raise PackageError(f"Symlink package entry: {canonical}")

        try:
            manifest = parse_manifest(archive.read(manifest_entries[0]))
        except (KeyError, OSError, RuntimeError, zipfile.BadZipFile) as error:
            raise PackageError("Delivery manifest is unreadable") from error
        manifest_paths = {entry["path"] for entry in manifest}
        package_paths = set(by_name) - {MANIFEST_NAME}
        missing = manifest_paths - package_paths
        if missing:
            raise PackageError(f"Missing package entry: {sorted(missing)[0]}")
        extra = package_paths - manifest_paths
        if extra:
            raise PackageError(f"Extra package entry: {sorted(extra)[0]}")

        for expected in manifest:
            relative = expected["path"]
            digest = hashlib.sha256()
            try:
                with archive.open(by_name[relative]) as source:
                    while chunk := source.read(HASH_CHUNK_SIZE):
                        digest.update(chunk)
            except (OSError, RuntimeError, zipfile.BadZipFile) as error:
                raise PackageError(f"Unreadable package entry: {relative}") from error
            if digest.hexdigest() != expected["sha256"]:
                raise PackageError(f"Package hash mismatch: {relative}")


def parser() -> argparse.ArgumentParser:
    argument_parser = argparse.ArgumentParser(description=__doc__)
    subparsers = argument_parser.add_subparsers(dest="command", required=True)
    build = subparsers.add_parser("build")
    build.add_argument("--root", required=True)
    build.add_argument("--output", required=True)
    verify = subparsers.add_parser("verify")
    verify.add_argument("--archive", required=True)
    return argument_parser


def main() -> int:
    arguments = parser().parse_args()
    try:
        if arguments.command == "build":
            build_archive(arguments.root, arguments.output)
        else:
            verify_archive(arguments.archive)
    except PackageError as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
