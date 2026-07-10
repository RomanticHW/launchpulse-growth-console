require "fileutils"
require "open3"
require "pathname"
require "tmpdir"

RSpec.describe "bin/package-demo" do
  let(:project_root) { Pathname(__dir__).join("../..").expand_path }

  def package_entries(source_root, git_shape:)
    Dir.mktmpdir("package-demo-checkout") do |tmpdir|
      checkout = Pathname(tmpdir).join("checkout")
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      FileUtils.mkdir_p(checkout.join("bin"))
      FileUtils.mkdir_p(checkout.join("docs/superpowers"))
      FileUtils.cp(source_root.join("bin/package-demo"), checkout.join("bin/package-demo"))
      FileUtils.cp(source_root.join("docs/demo-guide.md"), checkout.join("docs/demo-guide.md"))
      File.write(checkout.join("docs/superpowers/process-note.md"), "internal process note")
      create_git_metadata(checkout, git_shape)

      stdout, stderr, status = Open3.capture3("bash", checkout.join("bin/package-demo").to_s, output.to_s)
      expect(status).to be_success, -> { "Package failed:\n#{stdout}\n#{stderr}" }

      entries, list_stderr, list_status = Open3.capture3("unzip", "-Z1", output.to_s)
      expect(list_status).to be_success, -> { "Could not read package:\n#{list_stderr}" }
      entries.lines(chomp: true)
    end
  end

  def create_git_metadata(checkout, git_shape)
    case git_shape
    when :directory
      FileUtils.mkdir_p(checkout.join(".git"))
      File.write(checkout.join(".git/config"), "[core]\n")
    when :file
      File.write(checkout.join(".git"), "gitdir: ../repository/worktrees/checkout\n")
    else
      raise ArgumentError, "Unknown Git metadata shape: #{git_shape}"
    end
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

  def package_verifier(source_root)
    source = File.read(source_root.join("bin/package-demo"))
    match = source.match(/python3 - "\$OUTPUT" <<'PY'\n(?<script>.*?)\nPY\n/m)
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
end
