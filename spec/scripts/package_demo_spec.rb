require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

RSpec.describe "bin/package-demo" do
  let(:project_root) { Pathname(__dir__).join("../..").expand_path }

  def package_entries(source_root, git_shape:)
    Dir.mktmpdir("package-demo-checkout") do |tmpdir|
      checkout = create_checkout(source_root, tmpdir, git_shape:)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")

      stdout, stderr, status = Open3.capture3("bash", checkout.join("bin/package-demo").to_s, output.to_s)
      expect(status).to be_success, -> { "Package failed:\n#{stdout}\n#{stderr}" }
      zip_entries(output)
    end
  end

  def create_checkout(source_root, tmpdir, git_shape:)
    repository = Pathname(tmpdir).join("repository")
    FileUtils.mkdir_p(repository.join("bin"))
    FileUtils.mkdir_p(repository.join("docs/superpowers"))
    FileUtils.cp(source_root.join("bin/package-demo"), repository.join("bin/package-demo"))
    helper = source_root.join("bin/package_demo.py")
    FileUtils.cp(helper, repository.join("bin/package_demo.py")) if helper.exist?
    FileUtils.cp(source_root.join("docs/demo-guide.md"), repository.join("docs/demo-guide.md"))
    File.write(repository.join("docs/superpowers/process-note.md"), "internal process note")
    File.write(repository.join(".gitignore"), ".env.local\n*.pem\n")
    git(repository, "init", "--quiet")
    git(repository, "config", "user.email", "package-demo@example.test")
    git(repository, "config", "user.name", "Package Demo Test")
    tracked = [ ".gitignore", "bin/package-demo", "docs/demo-guide.md" ]
    tracked << "bin/package_demo.py" if helper.exist?
    git(repository, "add", *tracked)
    git(repository, "commit", "--quiet", "-m", "Create package fixture")

    case git_shape
    when :directory
      repository
    when :file
      checkout = Pathname(tmpdir).join("checkout")
      git(repository, "worktree", "add", "--quiet", "--detach", checkout.to_s, "HEAD")
      checkout
    else
      raise ArgumentError, "Unknown Git metadata shape: #{git_shape}"
    end
  end

  def git(repository, *arguments, stdin_data: "")
    stdout, stderr, status = Open3.capture3(
      "git", *arguments, chdir: repository.to_s, stdin_data:
    )
    expect(status).to be_success, -> { "Git command failed:\n#{stdout}\n#{stderr}" }
    stdout
  end

  def create_zip(path, *entries)
    script = <<~PYTHON
      import hashlib
      import json
      import sys
      import zipfile

      with zipfile.ZipFile(sys.argv[1], "w") as archive:
          for name in sys.argv[2:]:
              archive.writestr(name, "metadata")
          files = []
          for name in dict.fromkeys(sys.argv[2:]):
              if name == ".delivery-manifest.json":
                  continue
              files.append({"path": name, "sha256": hashlib.sha256(b"metadata").hexdigest()})
          manifest = {"version": 1, "files": files}
          archive.writestr(".delivery-manifest.json", json.dumps(manifest))
    PYTHON
    stdout, stderr, status = Open3.capture3("python3", "-c", script, path.to_s, *entries)
    expect(status).to be_success, -> { "Could not create test package:\n#{stdout}\n#{stderr}" }
  end

  def create_manifest_zip(path, entries:, manifest:, manifest_count: 1)
    fixture = {
      "entries" => entries,
      "manifest" => manifest,
      "manifest_count" => manifest_count
    }
    script = <<~PYTHON
      import json
      import stat
      import sys
      import zipfile

      fixture = json.load(sys.stdin)
      with zipfile.ZipFile(sys.argv[1], "w") as archive:
          for entry in fixture["entries"]:
              info = zipfile.ZipInfo(entry["path"])
              if entry.get("symlink"):
                  info.create_system = 3
                  info.external_attr = (stat.S_IFLNK | 0o777) << 16
              archive.writestr(info, entry.get("content", "fixture"))
          data = json.dumps(fixture["manifest"])
          for _index in range(fixture["manifest_count"]):
              archive.writestr(".delivery-manifest.json", data)
    PYTHON
    stdout, stderr, status = Open3.capture3(
      "python3", "-c", script, path.to_s, stdin_data: JSON.generate(fixture)
    )
    expect(status).to be_success, -> { "Could not create manifest fixture:\n#{stdout}\n#{stderr}" }
  end

  def zip_entries(path)
    script = <<~PYTHON
      import sys
      import zipfile

      with zipfile.ZipFile(sys.argv[1]) as archive:
          print("\\n".join(archive.namelist()))
    PYTHON
    stdout, stderr, status = Open3.capture3("python3", "-c", script, path.to_s)
    expect(status).to be_success, -> { "Could not read package:\n#{stderr}" }
    stdout.lines(chomp: true)
  end

  def zip_content(path, entry)
    script = <<~PYTHON
      import sys
      import zipfile

      with zipfile.ZipFile(sys.argv[1]) as archive:
          sys.stdout.buffer.write(archive.read(sys.argv[2]))
    PYTHON
    stdout, stderr, status = Open3.capture3("python3", "-c", script, path.to_s, entry)
    expect(status).to be_success, -> { "Could not read package entry:\n#{stderr}" }
    stdout
  end

  def extract_zip(path, destination)
    script = <<~PYTHON
      import pathlib
      import sys
      import zipfile

      destination = pathlib.Path(sys.argv[2])
      destination.mkdir(parents=True, exist_ok=True)
      with zipfile.ZipFile(sys.argv[1]) as archive:
          archive.extractall(destination)
    PYTHON
    stdout, stderr, status = Open3.capture3("python3", "-c", script, path.to_s, destination.to_s)
    expect(status).to be_success, -> { "Could not extract package:\n#{stdout}\n#{stderr}" }
  end

  def delivery_manifest(path)
    JSON.parse(zip_content(path, ".delivery-manifest.json"))
  end

  def track(checkout, relative_path, content, force: false)
    path = checkout.join(relative_path)
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, content)
    git(checkout, "add", *(force ? [ "-f" ] : []), "--", relative_path)
    git(checkout, "commit", "--quiet", "-m", "Track #{relative_path}")
  end

  def run_package(checkout, output)
    Open3.capture3("bash", checkout.join("bin/package-demo").to_s, output.to_s)
  end

  def expect_failed_package(checkout, output, relative_path)
    File.binwrite(output, "stale package")
    stdout, stderr, status = run_package(checkout, output)
    message = "#{stdout}\n#{stderr}"

    expect(status).not_to be_success
    expect(message).to include(relative_path)
    expect(message).not_to include(checkout.to_s)
    expect(output).not_to exist
    expect(Dir.glob(output.dirname.join(".package-demo.*").to_s)).to be_empty
    message
  end

  def verify_package(source_root, path)
    Open3.capture3(
      "python3",
      source_root.join("bin/package_demo.py").to_s,
      "verify",
      "--archive",
      path.to_s
    )
  end

  it "keeps public documentation in the delivery package" do
    entries = package_entries(project_root, git_shape: :directory)

    expect(entries).to include("docs/demo-guide.md")
  end

  it "packages only tracked files, excluding ignored secrets and ordinary untracked files" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      File.write(checkout.join(".env.local"), "IGNORED_ENV_SECRET")
      File.write(checkout.join("certificate.pem"), "IGNORED_PEM_SECRET")
      File.write(checkout.join("scratch.txt"), "ordinary untracked file")

      stdout, stderr, status = Open3.capture3("bash", checkout.join("bin/package-demo").to_s, output.to_s)

      expect(status).to be_success, -> { "Package failed:\n#{stdout}\n#{stderr}" }
      expect(zip_entries(output)).not_to include(".env.local", "certificate.pem", "scratch.txt")
    end
  end

  it "packages tracked files with spaces and Unicode names" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      track(checkout, "docs/release notes/版本说明.txt", "portable path")

      stdout, stderr, status = run_package(checkout, output)

      expect(status).to be_success, -> { "Package failed:\n#{stdout}\n#{stderr}" }
      expect(zip_entries(output)).to include("docs/release notes/版本说明.txt")
    end
  end

  it "packages the current working-tree content of modified tracked files" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      File.binwrite(checkout.join("docs/demo-guide.md"), "modified working-tree documentation")

      stdout, stderr, status = run_package(checkout, output)

      expect(status).to be_success, -> { "Package failed:\n#{stdout}\n#{stderr}" }
      expect(zip_content(output, "docs/demo-guide.md")).to eq("modified working-tree documentation")
      manifest_entry = delivery_manifest(output).fetch("files").find do |entry|
        entry.fetch("path") == "docs/demo-guide.md"
      end
      expect(manifest_entry.fetch("sha256")).to eq(Digest::SHA256.hexdigest("modified working-tree documentation"))
    end
  end

  it "embeds a root delivery manifest without a self entry" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")

      stdout, stderr, status = run_package(checkout, output)

      expect(status).to be_success, -> { "Package failed:\n#{stdout}\n#{stderr}" }
      manifest = delivery_manifest(output)
      paths = manifest.fetch("files").map { |entry| entry.fetch("path") }
      expect(manifest.fetch("version")).to eq(1)
      expect(paths).to contain_exactly(*git(checkout, "ls-files", "--cached").lines(chomp: true))
      expect(paths).not_to include(".delivery-manifest.json")
      expect(zip_entries(output)).to contain_exactly(*paths, ".delivery-manifest.json")
    end
  end

  it "repackages an unpacked delivery tree without Git metadata" do
    Dir.mktmpdir("package-demo-roundtrip") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :file)
      first_output = Pathname(tmpdir).join("first.zip")
      unpacked = Pathname(tmpdir).join("unpacked")
      second_output = Pathname(tmpdir).join("second.zip")
      first_stdout, first_stderr, first_status = run_package(checkout, first_output)
      expect(first_status).to be_success, -> { "Package failed:\n#{first_stdout}\n#{first_stderr}" }
      extract_zip(first_output, unpacked)

      stdout, stderr, status = run_package(unpacked, second_output)

      expect(status).to be_success, -> { "Repackage failed:\n#{stdout}\n#{stderr}" }
      expect(delivery_manifest(second_output)).to eq(delivery_manifest(first_output))
      expect(zip_entries(second_output)).to eq(zip_entries(second_output).uniq)
      verify_stdout, verify_stderr, verify_status = verify_package(project_root, second_output)
      expect(verify_status).to be_success, -> { "Verification failed:\n#{verify_stdout}\n#{verify_stderr}" }
    end
  end

  it "rejects a modified source in a non-Git delivery tree" do
    Dir.mktmpdir("package-demo-roundtrip") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :file)
      first_output = Pathname(tmpdir).join("first.zip")
      unpacked = Pathname(tmpdir).join("unpacked")
      second_output = Pathname(tmpdir).join("second.zip")
      _stdout, _stderr, status = run_package(checkout, first_output)
      expect(status).to be_success
      extract_zip(first_output, unpacked)
      secret = "MODIFIED_CONTENT_MUST_NOT_BE_PRINTED"
      File.binwrite(unpacked.join("docs/demo-guide.md"), secret)

      message = expect_failed_package(unpacked, second_output, "docs/demo-guide.md")

      expect(message).not_to include(secret)
    end
  end

  it "rejects a missing source in a non-Git delivery tree" do
    Dir.mktmpdir("package-demo-roundtrip") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :file)
      first_output = Pathname(tmpdir).join("first.zip")
      unpacked = Pathname(tmpdir).join("unpacked")
      second_output = Pathname(tmpdir).join("second.zip")
      _stdout, _stderr, status = run_package(checkout, first_output)
      expect(status).to be_success
      extract_zip(first_output, unpacked)
      FileUtils.rm(unpacked.join("docs/demo-guide.md"))

      expect_failed_package(unpacked, second_output, "docs/demo-guide.md")
    end
  end

  it "ignores extra ordinary files in a non-Git delivery tree" do
    Dir.mktmpdir("package-demo-roundtrip") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :file)
      first_output = Pathname(tmpdir).join("first.zip")
      unpacked = Pathname(tmpdir).join("unpacked")
      second_output = Pathname(tmpdir).join("second.zip")
      _stdout, _stderr, status = run_package(checkout, first_output)
      expect(status).to be_success
      extract_zip(first_output, unpacked)
      File.binwrite(unpacked.join("ordinary-extra.txt"), "not part of the delivery source")

      stdout, stderr, second_status = run_package(unpacked, second_output)

      expect(second_status).to be_success, -> { "Repackage failed:\n#{stdout}\n#{stderr}" }
      expect(zip_entries(second_output)).not_to include("ordinary-extra.txt")
      expect(delivery_manifest(second_output)).to eq(delivery_manifest(first_output))
    end
  end

  it "uses the delivery manifest when a non-Git root is nested in a parent repository" do
    Dir.mktmpdir("package-demo-parent-repository") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :file)
      first_output = Pathname(tmpdir).join("first.zip")
      _stdout, _stderr, status = run_package(checkout, first_output)
      expect(status).to be_success
      parent = Pathname(tmpdir).join("parent")
      unpacked = parent.join("delivery")
      extract_zip(first_output, unpacked)
      File.binwrite(unpacked.join("parent-only.txt"), "tracked only by the parent repository")
      git(parent, "init", "--quiet")
      git(parent, "config", "user.email", "package-demo@example.test")
      git(parent, "config", "user.name", "Package Demo Test")
      git(parent, "add", "-f", ".")
      git(parent, "commit", "--quiet", "-m", "Track parent fixture")
      second_output = Pathname(tmpdir).join("second.zip")

      stdout, stderr, second_status = run_package(unpacked, second_output)

      expect(second_status).to be_success, -> { "Repackage failed:\n#{stdout}\n#{stderr}" }
      expect(zip_entries(second_output)).not_to include("parent-only.txt")
      expect(delivery_manifest(second_output)).to eq(delivery_manifest(first_output))
    end
  end

  it "rejects a tracked delivery manifest reserved path" do
    Dir.mktmpdir("package-demo-reserved") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      track(checkout, ".delivery-manifest.json", "{}", force: true)

      expect_failed_package(checkout, output, ".delivery-manifest.json")
    end
  end

  it "rejects portable case collisions in the Git tracked-file manifest" do
    Dir.mktmpdir("package-demo-portable-collision") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      blob = git(checkout, "hash-object", "-w", "--stdin", stdin_data: "portable collision").strip
      index_entries = [ "docs/A.txt", "docs/a.txt" ].map do |path|
        "100644 #{blob} 0\t#{path}\n"
      end.join
      _stdout, _stderr, index_status = Open3.capture3(
        "git", "update-index", "--add", "--index-info", chdir: checkout.to_s, stdin_data: index_entries
      )
      skip("Git cannot construct a case-collision fixture on this platform") unless index_status.success?
      expect(git(checkout, "ls-files", "--cached", "docs/A.txt", "docs/a.txt").lines(chomp: true)).to contain_exactly(
        "docs/A.txt", "docs/a.txt"
      )

      package_stdout, package_stderr, status = run_package(checkout, output)

      expect(status).not_to be_success, -> { "Package unexpectedly passed:\n#{package_stdout}\n#{package_stderr}" }
      expect("#{package_stdout}\n#{package_stderr}").to include("docs/a.txt")
      expect(output).not_to exist
    end
  end

  it "rejects a tracked Windows reserved device path before packaging" do
    Dir.mktmpdir("package-demo-portable-path") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      track(checkout, "docs/CON.txt", "portable path fixture")

      _stdout, _stderr, status = run_package(checkout, output)

      expect(status).not_to be_success
      expect(output).not_to exist
    end
  end

  [
    ".env",
    ".envrc",
    "nested/.env.production",
    "nested/.ENV.production",
    "config/master.key",
    "config/demo.key",
    "config/tls/server.KEY",
    "config/credentials/production.key",
    "cert.pem",
    "cert.PEM",
    "client.p12",
    "client.P12",
    "client.pfx"
  ].each do |blocked_path|
    it "rejects the forcibly tracked secret #{blocked_path}" do
      Dir.mktmpdir("package-demo-secret") do |tmpdir|
        checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
        output = Pathname(tmpdir).join("launchpulse-demo.zip")
        secret = "DO_NOT_PRINT_SECRET_#{blocked_path.tr('/.', '_')}"
        track(checkout, blocked_path, secret, force: true)

        message = expect_failed_package(checkout, output, blocked_path)

        expect(message).not_to include(secret)
      end
    end
  end

  it "rejects a tracked local or internal artifact before packaging" do
    Dir.mktmpdir("package-demo-internal") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      track(checkout, "docs/superpowers/process-note.md", "internal", force: true)

      expect_failed_package(checkout, output, "docs/superpowers/process-note.md")
    end
  end

  it "rejects a missing tracked file and removes package artifacts" do
    Dir.mktmpdir("package-demo-missing") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      FileUtils.rm(checkout.join("docs/demo-guide.md"))

      expect_failed_package(checkout, output, "docs/demo-guide.md")
    end
  end

  it "rejects a tracked symlink and removes package artifacts" do
    Dir.mktmpdir("package-demo-symlink") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      File.symlink("../outside.txt", checkout.join("linked-source.txt"))
      git(checkout, "add", "linked-source.txt")
      git(checkout, "commit", "--quiet", "-m", "Track symlink fixture")

      expect_failed_package(checkout, output, "linked-source.txt")
    end
  end

  it "does not follow a parent directory replaced after path validation" do
    Dir.mktmpdir("package-demo-directory-swap") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      external_secret = "EXTERNAL_DIRECTORY_CONTENT_MUST_NOT_BE_PACKAGED"
      track(checkout, "safe/payload.txt", "tracked payload")
      FileUtils.mkdir_p(Pathname(tmpdir).join("outside"))
      File.binwrite(Pathname(tmpdir).join("outside/payload.txt"), external_secret)
      script_path = checkout.join("bin/package_demo.py")
      script = File.read(script_path)
      secure_open = "    try:\n        file_fd, metadata = open_regular(root_fd, path)"
      expect(script).to include(secure_open)
      directory_swap = [
        %(    if relative == "safe/payload.txt":),
        %(        safe_directory = #{JSON.generate(checkout.join("safe").to_s)}),
        %(        os.rename(safe_directory, safe_directory + "-original")),
        %(        os.symlink(#{JSON.generate(Pathname(tmpdir).join("outside").to_s)}, safe_directory)),
        ""
      ].join("\n")
      File.write(script_path, script.sub(secure_open, directory_swap + secure_open))
      File.binwrite(output, "stale package")

      stdout, stderr, status = run_package(checkout, output)
      message = "#{stdout}\n#{stderr}"
      leaked = status.success? && zip_content(output, "safe/payload.txt") == external_secret

      expect([ status.success?, leaked ]).to eq([ false, false ])
      expect(message).to include("safe/payload.txt")
      expect(message).not_to include(external_secret, checkout.to_s)
      expect(output).not_to exist
      expect(Dir.glob(Pathname(tmpdir).join(".package-demo.*").to_s)).to be_empty
    end
  end

  it "rejects duplicate paths from an unmerged Git index" do
    Dir.mktmpdir("package-demo-unmerged") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      track(checkout, "conflict.txt", "working tree content")
      blobs = %w[base ours theirs].map do |content|
        git(checkout, "hash-object", "-w", "--stdin", stdin_data: content).strip
      end
      index_entries = blobs.each_with_index.map do |blob, index|
        "100644 #{blob} #{index + 1}\tconflict.txt\n"
      end.join
      git(checkout, "update-index", "--force-remove", "--", "conflict.txt")
      git(checkout, "update-index", "--index-info", stdin_data: index_entries)
      tracked = git(checkout, "ls-files", "--cached", "--", "conflict.txt").lines(chomp: true)
      expect(tracked).to eq([ "conflict.txt", "conflict.txt", "conflict.txt" ])

      expect_failed_package(checkout, output, "conflict.txt")
    end
  end

  it "keeps the existing non-ASCII readme filename restriction" do
    Dir.mktmpdir("package-demo-readme") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      track(checkout, "readme/技术说明.md", "documentation")

      expect_failed_package(checkout, output, "readme/技术说明.md")
    end
  end

  it "excludes internal process documents from the delivery package" do
    entries = package_entries(project_root, git_shape: :directory)

    expect(entries.grep(%r{\Adocs/superpowers(?:/|\z)})).to be_empty
  end

  it "excludes Git directory metadata from a normal checkout" do
    entries = package_entries(project_root, git_shape: :directory)

    expect(entries.grep(%r{\A\.git(?:/|\z)})).to be_empty
  end

  it "excludes the Git pointer file from a linked worktree" do
    entries = package_entries(project_root, git_shape: :file)

    expect(entries).not_to include(".git")
  end

  it "rejects an injected Git directory from the package manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("directory-metadata.zip")
      create_zip(package, ".git/", ".git/config")

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      expect(stderr).to include("Unsafe package entry")
    end
  end

  it "rejects an injected Git pointer file from the package manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("pointer-metadata.zip")
      create_zip(package, ".git")

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      expect(stderr).to include(".git")
    end
  end

  it "rejects an injected internal process document from the package manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("internal-document.zip")
      create_zip(package, "docs/superpowers/process-note.md")

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      expect(stderr).to include("docs/superpowers/process-note.md")
    end
  end

  it "rejects injected secrets from the package manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("injected-secrets.zip")
      secrets = [
        ".env",
        ".envrc",
        "nested/.env.production",
        "nested/.ENV.production",
        "config/master.key",
        "config/demo.key",
        "config/tls/server.KEY",
        "config/credentials/production.key",
        "CERT.PEM",
        "client.P12",
        "client.pfx"
      ]
      secrets.each do |path|
        create_zip(package, path)
        _stdout, stderr, status = verify_package(project_root, package)
        expect(status).not_to be_success
        expect(stderr).to include(path)
      end
    end
  end

  it "rejects injected local and internal entries from the package manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("injected-internal.zip")
      blocked = [
        "__MACOSX/metadata",
        "tmp/cache/item",
        "log/development.log",
        "storage/blob",
        "output/report.txt",
        ".playwright-cli/session.json",
        "docs/superpowers/plan.md",
        "vendor/bundle/gem",
        "public/assets/application.css",
        "app/assets/builds/application.css",
        ".bundle/config",
        "coverage/index.html",
        ".DS_Store"
      ]
      blocked.each do |path|
        create_zip(package, path)
        _stdout, stderr, status = verify_package(project_root, package)
        expect(status).not_to be_success
        expect(stderr).to include(path)
      end
    end
  end

  it "rejects duplicate entries from the package manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("duplicate-entry.zip")
      create_zip(package, "duplicate.txt", "duplicate.txt")

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      expect(stderr).to include("duplicate.txt")
    end
  end

  it "rejects a portable alias beside the exact root delivery manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("manifest-alias.zip")
      content = "alias content"
      alias_path = ".DELIVERY-MANIFEST.JSON"
      create_manifest_zip(
        package,
        entries: [ { "path" => alias_path, "content" => content } ],
        manifest: {
          "version" => 1,
          "files" => [ { "path" => alias_path, "sha256" => Digest::SHA256.hexdigest(content) } ]
        }
      )

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      expect(stderr).not_to include(content)
    end
  end

  it "rejects case and Unicode normalization collisions in ZIP paths" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("portable-collision.zip")
      collisions = [
        [ "docs/A.txt", "docs/a.txt" ],
        [ "docs/café.txt", "docs/cafe\u0301.txt" ]
      ]
      collisions.each do |paths|
        entries = paths.map { |path| { "path" => path, "content" => "fixture" } }
        files = [ { "path" => paths.first, "sha256" => Digest::SHA256.hexdigest("fixture") } ]
        create_manifest_zip(package, entries:, manifest: { "version" => 1, "files" => files })

        _stdout, _stderr, status = verify_package(project_root, package)

        expect(status).not_to be_success
      end
    end
  end

  it "rejects case and Unicode normalization collisions in manifest paths" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("portable-manifest-collision.zip")
      collisions = [
        [ "docs/A.txt", "docs/a.txt" ],
        [ "docs/café.txt", "docs/cafe\u0301.txt" ]
      ]
      collisions.each do |paths|
        files = paths.map do |path|
          { "path" => path, "sha256" => Digest::SHA256.hexdigest("fixture") }
        end
        create_manifest_zip(
          package,
          entries: [ { "path" => paths.first, "content" => "fixture" } ],
          manifest: { "version" => 1, "files" => files }
        )

        _stdout, _stderr, status = verify_package(project_root, package)

        expect(status).not_to be_success
      end
    end
  end

  it "rejects Windows reserved device names in any path component" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("windows-reserved-path.zip")
      reserved = %w[CON PRN AUX NUL COM1 COM2 COM3 COM4 COM5 COM6 COM7 COM8 COM9
                    LPT1 LPT2 LPT3 LPT4 LPT5 LPT6 LPT7 LPT8 LPT9 CON.txt]
      reserved.each do |component|
        path = "docs/#{component}/payload.txt"
        create_manifest_zip(
          package,
          entries: [ { "path" => path, "content" => "fixture" } ],
          manifest: {
            "version" => 1,
            "files" => [ { "path" => path, "sha256" => Digest::SHA256.hexdigest("fixture") } ]
          }
        )

        _stdout, _stderr, status = verify_package(project_root, package)

        expect(status).not_to be_success
      end
    end
  end

  it "rejects non-portable component endings, control characters, and Windows-invalid characters" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("invalid-portable-path.zip")
      paths = [
        "docs/trailing-space ",
        "docs/trailing-dot.",
        "docs/control-\u0001.txt",
        'docs/less<than.txt',
        'docs/greater>than.txt',
        'docs/colon:name.txt',
        'docs/quote"name.txt',
        "docs/pipe|name.txt",
        "docs/question?.txt",
        "docs/star*.txt"
      ]
      paths.each do |path|
        create_manifest_zip(
          package,
          entries: [ { "path" => path, "content" => "fixture" } ],
          manifest: {
            "version" => 1,
            "files" => [ { "path" => path, "sha256" => Digest::SHA256.hexdigest("fixture") } ]
          }
        )

        _stdout, stderr, status = verify_package(project_root, package)

        expect(status).not_to be_success
        expect(stderr).not_to include("fixture")
      end
    end
  end

  it "requires exactly one root delivery manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("missing-manifest.zip")
      create_manifest_zip(package, entries: [], manifest: { "version" => 1, "files" => [] }, manifest_count: 0)
      _stdout, stderr, status = verify_package(project_root, package)
      expect(status).not_to be_success
      expect(stderr).to include("exactly once")

      create_manifest_zip(package, entries: [], manifest: { "version" => 1, "files" => [] }, manifest_count: 2)
      _stdout, stderr, status = verify_package(project_root, package)
      expect(status).not_to be_success
      expect(stderr).to include("exactly once")
    end
  end

  it "rejects duplicate paths in the delivery manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("duplicate-manifest-path.zip")
      digest = Digest::SHA256.hexdigest("fixture")
      file = { "path" => "docs/demo.txt", "sha256" => digest }
      create_manifest_zip(
        package,
        entries: [ { "path" => "docs/demo.txt", "content" => "fixture" } ],
        manifest: { "version" => 1, "files" => [ file, file ] }
      )

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      expect(stderr).to include("Duplicate manifest path: docs/demo.txt")
    end
  end

  it "rejects missing and extra ZIP entries relative to the delivery manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("entry-set-mismatch.zip")
      digest = Digest::SHA256.hexdigest("fixture")
      create_manifest_zip(
        package,
        entries: [],
        manifest: { "version" => 1, "files" => [ { "path" => "missing.txt", "sha256" => digest } ] }
      )
      _stdout, missing_stderr, missing_status = verify_package(project_root, package)
      expect(missing_status).not_to be_success
      expect(missing_stderr).to include("Missing package entry: missing.txt")

      create_manifest_zip(
        package,
        entries: [ { "path" => "extra.txt", "content" => "fixture" } ],
        manifest: { "version" => 1, "files" => [] }
      )
      _stdout, extra_stderr, extra_status = verify_package(project_root, package)
      expect(extra_status).not_to be_success
      expect(extra_stderr).to include("Extra package entry: extra.txt")
    end
  end

  it "rejects traversal and reserved paths in the delivery manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("unsafe-manifest-path.zip")
      digest = Digest::SHA256.hexdigest("fixture")
      [ "../outside.txt", ".delivery-manifest.json" ].each do |path|
        create_manifest_zip(
          package,
          entries: [],
          manifest: { "version" => 1, "files" => [ { "path" => path, "sha256" => digest } ] }
        )
        _stdout, _stderr, status = verify_package(project_root, package)
        expect(status).not_to be_success
      end
    end
  end

  it "rejects a blocked nested secret in the delivery manifest without printing its content" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("blocked-manifest-path.zip")
      path = "config/tls/server.KEY"
      secret = "NESTED_SECRET_MUST_NOT_BE_PRINTED"
      create_manifest_zip(
        package,
        entries: [ { "path" => path, "content" => secret } ],
        manifest: {
          "version" => 1,
          "files" => [ { "path" => path, "sha256" => Digest::SHA256.hexdigest(secret) } ]
        }
      )

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      expect(stderr).to include(path)
      expect(stderr).not_to include(secret)
    end
  end

  it "rejects invalid and mismatched manifest hashes" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("invalid-manifest-hash.zip")
      entries = [ { "path" => "docs/demo.txt", "content" => "fixture" } ]
      create_manifest_zip(
        package,
        entries:,
        manifest: { "version" => 1, "files" => [ { "path" => "docs/demo.txt", "sha256" => "z" * 64 } ] }
      )
      _stdout, invalid_stderr, invalid_status = verify_package(project_root, package)
      expect(invalid_status).not_to be_success
      expect(invalid_stderr).to include("Invalid manifest hash: docs/demo.txt")

      create_manifest_zip(
        package,
        entries:,
        manifest: {
          "version" => 1,
          "files" => [ { "path" => "docs/demo.txt", "sha256" => Digest::SHA256.hexdigest("different") } ]
        }
      )
      _stdout, mismatch_stderr, mismatch_status = verify_package(project_root, package)
      expect(mismatch_status).not_to be_success
      expect(mismatch_stderr).to include("Package hash mismatch: docs/demo.txt")
    end
  end

  it "rejects a symlink ZIP entry named by the delivery manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("symlink-entry.zip")
      create_manifest_zip(
        package,
        entries: [ { "path" => "linked.txt", "content" => "target.txt", "symlink" => true } ],
        manifest: {
          "version" => 1,
          "files" => [ { "path" => "linked.txt", "sha256" => Digest::SHA256.hexdigest("target.txt") } ]
        }
      )

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      expect(stderr).to include("Symlink package entry: linked.txt")
    end
  end

  it "rejects a project-internal output path before creating artifacts" do
    Dir.mktmpdir("package-demo-inside-", project_root.join("tmp").to_s) do |tmpdir|
      output = Pathname(tmpdir).join("launchpulse-demo.zip")

      _stdout, stderr, status = Open3.capture3(project_root.join("bin/package-demo").to_s, output.to_s)

      expect(status).not_to be_success
      expect(stderr).to include("Output path must be outside project root:")
      expect(output).not_to exist
      expect(Dir.glob(File.join(tmpdir, ".package-demo.*"))).to be_empty
    end
  end

  it "allows an external sibling output path with the same prefix" do
    prefix = "#{project_root.basename}-copy-"

    Dir.mktmpdir(prefix, project_root.dirname.to_s) do |tmpdir|
      output = Pathname(tmpdir).join("launchpulse-demo.zip")

      stdout, stderr, status = Open3.capture3(project_root.join("bin/package-demo").to_s, output.to_s)

      expect(status).to be_success, -> { "Package failed:\n#{stdout}\n#{stderr}" }
      expect(output).to exist
      expect(zip_entries(output)).to include("docs/demo-guide.md")
      expect(Dir.glob(File.join(tmpdir, ".package-demo.*"))).to be_empty
    end
  end
end
