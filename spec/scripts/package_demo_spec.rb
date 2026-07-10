require "rails_helper"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe "bin/package-demo" do
  it "excludes local Git worktrees from the delivery archive" do
    marker_dir = Rails.root.join(".worktrees", "package-demo-spec")
    marker = marker_dir.join("local-only.txt")
    FileUtils.mkdir_p(marker_dir)
    marker.write("local development artifact")

    Dir.mktmpdir do |directory|
      archive = File.join(directory, "launchpulse-demo.zip")
      _stdout, stderr, status = Open3.capture3(Rails.root.join("bin/package-demo").to_s, archive)

      expect(status).to be_success, stderr

      entries, list_stderr, list_status = Open3.capture3("unzip", "-Z1", archive)
      expect(list_status).to be_success, list_stderr
      expect(entries.lines.grep(%r{\A\.worktrees/})).to be_empty
    end
  ensure
    FileUtils.rm_rf(marker_dir)
  end

  it "does not retain empty directory entries after ignored files are excluded" do
    marker_dir = Rails.root.join("docs", ".internal-notes")
    marker = marker_dir.join(".DS_Store")
    FileUtils.mkdir_p(marker_dir)
    marker.write("local metadata")

    Dir.mktmpdir do |directory|
      archive = File.join(directory, "launchpulse-demo.zip")
      _stdout, stderr, status = Open3.capture3(Rails.root.join("bin/package-demo").to_s, archive)

      expect(status).to be_success, stderr

      entries, list_stderr, list_status = Open3.capture3("unzip", "-Z1", archive)
      expect(list_status).to be_success, list_stderr
      expect(entries.lines.grep(%r{\Adocs/\.internal-notes(?:/|\z)})).to be_empty
    end
  ensure
    FileUtils.rm_f(marker)
    Dir.rmdir(marker_dir) if marker_dir&.directory? && marker_dir.empty?
  end
end
