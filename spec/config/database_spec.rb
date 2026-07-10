require "rails_helper"

RSpec.describe "production database configuration" do
  CONFIG_DATABASE_URL_ERROR_MESSAGE = "Database URL must be a valid PostgreSQL URL with a database path"
  DATABASE_URL_KEYS = %w[
    DATABASE_URL
    CACHE_DATABASE_URL
    QUEUE_DATABASE_URL
    CABLE_DATABASE_URL
    LAUNCH_PULSE_DATABASE_PASSWORD
  ].freeze
  CONNECTION_URL_KEYS = DATABASE_URL_KEYS.first(4).freeze
  CONFIG_INVALID_DATABASE_URLS = [
    "mysql://sentinel_user:sentinel_password@sentinel_host/sentinel_database",
    "postgresql://sentinel_user:sentinel_password@sentinel_host/sentinel%ZZ",
    "postgresql://sentinel_user:sentinel_password@[2001:db8::1/sentinel_database",
    "postgresql://sentinel_user:sentinel_password@sentinel_host/"
  ].freeze

  def production_configurations(env)
    original_env = DATABASE_URL_KEYS.to_h { |key| [ key, ENV[key] ] }
    env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    allow(ActiveRecord::ConnectionHandling::DEFAULT_ENV).to receive(:call).and_return("production")

    raw_config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/database.yml"))
    ActiveRecord::DatabaseConfigurations
      .new(raw_config)
      .configs_for(env_name: "production", include_hidden: true)
      .index_by(&:name)
      .transform_values(&:configuration_hash)
  ensure
    original_env&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it "derives independent production databases from DATABASE_URL when dedicated URLs are absent" do
    configurations = production_configurations(
      "DATABASE_URL" => "postgresql://shared%2Duser:shared%40password@[2001:db8::1]:6543/shared%2Ddatabase?sslmode=require&application_name=launch%20pulse",
      "CACHE_DATABASE_URL" => nil,
      "QUEUE_DATABASE_URL" => nil,
      "CABLE_DATABASE_URL" => nil
    )

    expect(configurations.keys).to contain_exactly("primary", "cache", "queue", "cable")
    inherited_connection = configurations.fetch("primary").slice(
      :adapter,
      :host,
      :port,
      :username,
      :password,
      :sslmode,
      :application_name
    )
    expect(configurations.transform_values { |configuration| configuration.slice(*inherited_connection.keys) }.values)
      .to all(eq(inherited_connection))
    expect(inherited_connection.except(:password)).to eq(
      adapter: "postgresql",
      host: "2001:db8::1",
      port: 6543,
      username: "shared-user",
      sslmode: "require",
      application_name: "launch pulse"
    )
    expect(inherited_connection[:password]).to be_present
    expect(configurations.transform_values { |configuration| configuration[:database] }).to eq(
      "primary" => "shared-database",
      "cache" => "shared-database_cache",
      "queue" => "shared-database_queue",
      "cable" => "shared-database_cable"
    )
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

  it "accepts postgres URLs without a host and still derives independent databases" do
    configurations = production_configurations(
      "DATABASE_URL" => "postgres:///socket_database?username=socket_user",
      "CACHE_DATABASE_URL" => nil,
      "QUEUE_DATABASE_URL" => nil,
      "CABLE_DATABASE_URL" => nil
    )

    expect(configurations.transform_values { |configuration| configuration.values_at(:host, :username, :database) }).to eq(
      "primary" => [ nil, "socket_user", "socket_database" ],
      "cache" => [ nil, "socket_user", "socket_database_cache" ],
      "queue" => [ nil, "socket_user", "socket_database_queue" ],
      "cable" => [ nil, "socket_user", "socket_database_cable" ]
    )
  end

  it "rejects every invalid production URL with one sanitized error" do
    CONNECTION_URL_KEYS.product(CONFIG_INVALID_DATABASE_URLS).each do |key, invalid_url|
      env = CONNECTION_URL_KEYS.to_h { |url_key| [ url_key, nil ] }.merge(key => invalid_url)

      expect do
        production_configurations(env)
      end.to raise_error(ArgumentError) { |error|
        expect(error.message).to eq(CONFIG_DATABASE_URL_ERROR_MESSAGE)
        expect(error.message).not_to include("sentinel_user", "sentinel_password", "sentinel_host")
      }
    end
  end
end
