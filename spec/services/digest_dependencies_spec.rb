require "rails_helper"

RSpec.describe "Digest dependencies" do
  it "loads digest explicitly in services that calculate SHA256 values" do
    service_paths = %w[
      app/services/events/ingestion_service.rb
      app/services/events/payload_fingerprint.rb
      app/services/sites/snapshot_service.rb
    ]

    service_paths.each do |path|
      source = Rails.root.join(path).read

      expect(source).to include('require "digest"'), "#{path} must explicitly load digest"
    end
  end
end
