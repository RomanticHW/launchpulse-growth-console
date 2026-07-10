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
    checkout = Pathname(tmpdir).join("checkout")
    FileUtils.mkdir_p(checkout.join("bin"))
    FileUtils.mkdir_p(checkout.join("docs/superpowers"))
    FileUtils.cp(source_root.join("bin/package-demo"), checkout.join("bin/package-demo"))
    FileUtils.cp(source_root.join("docs/demo-guide.md"), checkout.join("docs/demo-guide.md"))
    File.write(checkout.join("docs/superpowers/process-note.md"), "internal process note")
    create_git_metadata(checkout, git_shape)
    checkout
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

  it "leaves no package artifacts when verification fails" do
    Dir.mktmpdir("package-demo-failure") do |tmpdir|
      checkout = create_checkout(project_root, tmpdir, git_shape: :directory)
      script_path = checkout.join("bin/package-demo")
      script = File.read(script_path)
      exclusion = %(  -x "docs/superpowers/*" \\\n)
      expect(script).to include(exclusion)
      File.write(script_path, script.sub(exclusion, ""))
      output = Pathname(tmpdir).join("launchpulse-demo.zip")
      File.write(output, "stale package")

      stdout, stderr, status = Open3.capture3("bash", script_path.to_s, output.to_s)

      expect(status).not_to be_success
      expect("#{stdout}\n#{stderr}").to include("Unexpected local artifacts in package: docs/superpowers/")
      expect(output).not_to exist
      expect(Dir.glob(File.join(tmpdir, ".package-demo.*"))).to be_empty
    end
  end
end
