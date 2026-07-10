require "fileutils"
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
    FileUtils.cp(source_root.join("docs/demo-guide.md"), repository.join("docs/demo-guide.md"))
    File.write(repository.join("docs/superpowers/process-note.md"), "internal process note")
    File.write(repository.join(".gitignore"), ".env.local\n*.pem\n")
    git(repository, "init", "--quiet")
    git(repository, "config", "user.email", "package-demo@example.test")
    git(repository, "config", "user.name", "Package Demo Test")
    git(repository, "add", ".gitignore", "bin/package-demo", "docs/demo-guide.md")
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

  def git(repository, *arguments)
    stdout, stderr, status = Open3.capture3("git", *arguments, chdir: repository.to_s)
    expect(status).to be_success, -> { "Git command failed:\n#{stdout}\n#{stderr}" }
    stdout
  end

  def create_zip(path, *entries)
    script = <<~PYTHON
      import sys
      import zipfile

      with zipfile.ZipFile(sys.argv[1], "w") as archive:
          for name in sys.argv[2:]:
              archive.writestr(name, "metadata")
    PYTHON
    stdout, stderr, status = Open3.capture3("python3", "-c", script, path.to_s, *entries)
    expect(status).to be_success, -> { "Could not create test package:\n#{stdout}\n#{stderr}" }
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

  def package_verifier(source_root)
    source = File.read(source_root.join("bin/package-demo"))
    match = source.match(/python3 - "\$(?:OUTPUT|TEMP_OUTPUT)" <<'PY'\n(?<script>.*?)\nPY\n/m)
    raise "Package verifier was not found" unless match

    match[:script]
  end

  def verify_package(source_root, path)
    Open3.capture3("python3", "-", path.to_s, stdin_data: package_verifier(source_root))
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
    end
  end

  [
    ".env",
    "nested/.env.production",
    "config/master.key",
    "config/demo.key",
    "config/credentials/production.key",
    "cert.pem",
    "client.p12",
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
      expect(stderr).to include("Unexpected local artifacts in package: .git/, .git/config")
    end
  end

  it "rejects an injected Git pointer file from the package manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("pointer-metadata.zip")
      create_zip(package, ".git")

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      expect(stderr).to include("Unexpected local artifacts in package: .git")
    end
  end

  it "rejects an injected internal process document from the package manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("internal-document.zip")
      create_zip(package, "docs/superpowers/process-note.md")

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      expect(stderr).to include("Unexpected local artifacts in package: docs/superpowers/process-note.md")
    end
  end

  it "rejects injected secrets from the package manifest" do
    Dir.mktmpdir("package-demo-manifest") do |tmpdir|
      package = Pathname(tmpdir).join("injected-secrets.zip")
      secrets = [
        ".env",
        "nested/.env.production",
        "config/master.key",
        "config/demo.key",
        "config/credentials/production.key",
        "CERT.PEM",
        "client.P12",
        "client.pfx"
      ]
      create_zip(package, *secrets)

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      secrets.each { |path| expect(stderr).to include(path) }
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
      create_zip(package, *blocked)

      _stdout, stderr, status = verify_package(project_root, package)

      expect(status).not_to be_success
      blocked.each { |path| expect(stderr).to include(path) }
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
