require "rails_helper"
require "erb"
require "yaml"

RSpec.describe "production database configuration" do
  DATABASE_URL_KEYS = %w[
    DATABASE_URL
    CACHE_DATABASE_URL
    QUEUE_DATABASE_URL
    CABLE_DATABASE_URL
    LAUNCH_PULSE_DATABASE_PASSWORD
  ].freeze

  def production_configurations(env)
    original_env = DATABASE_URL_KEYS.to_h { |key| [ key, ENV[key] ] }
    env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    allow(ActiveRecord::ConnectionHandling::DEFAULT_ENV).to receive(:call).and_return("production")

    rendered = ERB.new(Rails.root.join("config/database.yml").read).result
    raw_config = YAML.safe_load(rendered, aliases: true)
    ActiveRecord::DatabaseConfigurations
      .new(raw_config)
      .configs_for(env_name: "production", include_hidden: true)
      .index_by(&:name)
      .transform_values(&:configuration_hash)
  ensure
    original_env&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it "uses DATABASE_URL for all production connections when dedicated URLs are absent" do
    configurations = production_configurations(
      "DATABASE_URL" => "postgresql://shared_user:shared_password@db.example.test:6543/shared_database",
      "CACHE_DATABASE_URL" => nil,
      "QUEUE_DATABASE_URL" => nil,
      "CABLE_DATABASE_URL" => nil
    )

    expect(configurations.keys).to contain_exactly("primary", "cache", "queue", "cable")
    configurations.each_value do |configuration|
      expect(configuration).to include(
        adapter: "postgresql",
        host: "db.example.test",
        port: 6543,
        username: "shared_user",
        password: "shared_password",
        database: "shared_database"
      )
    end
  end

  it "lets each dedicated URL override the shared DATABASE_URL" do
    configurations = production_configurations(
      "DATABASE_URL" => "postgresql://primary_user:primary_password@primary.example.test:6432/primary_database",
      "CACHE_DATABASE_URL" => "postgresql://cache_user:cache_password@cache.example.test:6433/cache_database",
      "QUEUE_DATABASE_URL" => "postgresql://queue_user:queue_password@queue.example.test:6434/queue_database",
      "CABLE_DATABASE_URL" => "postgresql://cable_user:cable_password@cable.example.test:6435/cable_database"
    )

    expect(configurations.transform_values { |configuration| configuration.values_at(:host, :port, :username, :database) }).to eq(
      "primary" => [ "primary.example.test", 6432, "primary_user", "primary_database" ],
      "cache" => [ "cache.example.test", 6433, "cache_user", "cache_database" ],
      "queue" => [ "queue.example.test", 6434, "queue_user", "queue_database" ],
      "cable" => [ "cable.example.test", 6435, "cable_user", "cable_database" ]
    )
  end

  it "keeps the named database fallback when no URLs are provided" do
    configurations = production_configurations(
      "DATABASE_URL" => nil,
      "CACHE_DATABASE_URL" => nil,
      "QUEUE_DATABASE_URL" => nil,
      "CABLE_DATABASE_URL" => nil,
      "LAUNCH_PULSE_DATABASE_PASSWORD" => "legacy_password"
    )

    expect(configurations.transform_values { |configuration| configuration[:database] }).to eq(
      "primary" => "launch_pulse_production",
      "cache" => "launch_pulse_production_cache",
      "queue" => "launch_pulse_production_queue",
      "cable" => "launch_pulse_production_cable"
    )
    expect(configurations.values).to all(include(username: "launch_pulse", password: "legacy_password"))
  end
end
