require "fileutils"
require "open3"
require "pathname"
require "tmpdir"

RSpec.describe "bin/package-demo" do
  def package_entries(root)
    Dir.mktmpdir("launchpulse-package") do |tmpdir|
      output = File.join(tmpdir, "launchpulse-demo.zip")
      stdout, stderr, status = Open3.capture3(root.join("bin/package-demo").to_s, output, chdir: root.to_s)

      expect(status).to be_success, -> { "Package failed:\n#{stdout}\n#{stderr}" }

      entries, list_stderr, list_status = Open3.capture3("unzip", "-Z1", output)
      expect(list_status).to be_success, -> { "Could not read package:\n#{list_stderr}" }
      entries.lines(chomp: true)
    end
  end

  it "excludes internal process documents from the delivery package" do
    root = Pathname(__dir__).join("../..").expand_path
    probe = root.join("docs/superpowers/package-exclusion-probe.txt")

    begin
      FileUtils.mkdir_p(probe.dirname)
      File.write(probe, "internal process note")

      expect(package_entries(root).grep(%r{\Adocs/superpowers(?:/|\z)})).to be_empty
    ensure
      FileUtils.rm_f(probe)
    end
  end

  it "excludes Git metadata from the delivery package" do
    root = Pathname(__dir__).join("../..").expand_path

    expect(package_entries(root).grep(%r{\A\.git(?:/|\z)})).to be_empty
  end
end
