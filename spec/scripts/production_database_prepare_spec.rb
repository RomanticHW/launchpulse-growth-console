require "rails_helper"
require "cgi"
require "open3"
require "pg"
require "timeout"
require "uri"

RSpec.describe "production database preparation" do
  self.use_transactional_tests = false

  PREPARE_TIMEOUT = 90
  CONNECTION_QUERY_KEYS = %i[sslmode sslcert sslkey sslrootcert connect_timeout].freeze

  it "prepares each production database derived from one DATABASE_URL" do
    expect(database_creator?).to be(true), <<~MESSAGE
      当前 PostgreSQL 角色缺少 CREATEDB 权限，无法验证单 URL 派生数据库。
      请授予 CREATEDB，或在部署前预先创建 primary/cache/queue/cable 数据库。
    MESSAGE

    base_name = "launch_pulse_prepare_#{Process.pid}_#{SecureRandom.hex(6)}"
    databases = {
      primary: base_name,
      cache: "#{base_name}_cache",
      queue: "#{base_name}_queue",
      cable: "#{base_name}_cable"
    }
    connections = []
    database_url = database_url_for(base_name)
    stdout, stderr, status = run_prepare(database_url)
    expect(status).to be_success, sanitized_process_failure(stdout, stderr)

    expected_tables = {
      primary: "events",
      cache: "solid_cache_entries",
      queue: "solid_queue_jobs",
      cable: "solid_cable_messages"
    }
    expected_tables.each do |role, table|
      connection = PG.connect(postgres_connection_params(databases.fetch(role)))
      connections << connection
      present = connection.exec_params("SELECT to_regclass($1) IS NOT NULL", [ "public.#{table}" ]).getvalue(0, 0)
      expect(present).to eq("t"), "#{role} database #{databases.fetch(role)} is missing #{table}"
    end
  ensure
    connections&.each { |connection| connection.finish unless connection.finished? }
    databases&.each_value { |database| drop_database(database) }
  end

  private

  def connection_config
    @connection_config ||= ActiveRecord::Base.connection_db_config.configuration_hash
  end

  def database_creator?
    ActiveRecord::Base.connection.select_value(<<~SQL).in?([ true, "t" ])
      SELECT rolcreatedb OR rolsuper
      FROM pg_roles
      WHERE rolname = current_user
    SQL
  end

  def database_url_for(database)
    host = connection_config[:host]
    query = connection_config.slice(*CONNECTION_QUERY_KEYS).compact
    userinfo = encoded_userinfo
    if host&.start_with?("/")
      query[:host] = host
      host = nil
    elsif host&.include?(":") && !host.start_with?("[")
      host = "[#{host}]"
    end
    if host.blank?
      query[:username] = connection_username
      query[:password] = connection_config[:password] if connection_config[:password].present?
      userinfo = nil
    end

    URI::Generic.build(
      scheme: "postgresql",
      userinfo:,
      host: host || "",
      port: connection_config[:port]&.to_i,
      path: "/#{database}",
      query: query.present? ? URI.encode_www_form(query) : nil
    ).to_s
  end

  def encoded_userinfo
    username = connection_username
    return if username.blank?

    encoded = CGI.escapeURIComponent(username.to_s)
    password = connection_config[:password]
    password.present? ? "#{encoded}:#{CGI.escapeURIComponent(password.to_s)}" : encoded
  end

  def connection_username
    connection_config[:username].presence || ActiveRecord::Base.connection.select_value("SELECT current_user")
  end

  def postgres_connection_params(database)
    {
      dbname: database,
      host: connection_config[:host],
      port: connection_config[:port],
      user: connection_config[:username],
      password: connection_config[:password],
      sslmode: connection_config[:sslmode],
      connect_timeout: connection_config[:connect_timeout]
    }.compact
  end

  def run_prepare(database_url)
    env = {
      "RAILS_ENV" => "production",
      "DATABASE_URL" => database_url,
      "CACHE_DATABASE_URL" => nil,
      "QUEUE_DATABASE_URL" => nil,
      "CABLE_DATABASE_URL" => nil,
      "SECRET_KEY_BASE" => SecureRandom.hex(64),
      "DISABLE_DATABASE_ENVIRONMENT_CHECK" => "1",
      "RAILS_LOG_LEVEL" => "fatal"
    }

    Open3.popen3(env, Rails.root.join("bin/rails").to_s, "db:prepare", chdir: Rails.root.to_s) do |stdin, stdout, stderr, wait_thread|
      stdin.close
      stdout_reader = Thread.new { stdout.read }
      stderr_reader = Thread.new { stderr.read }

      begin
        status = Timeout.timeout(PREPARE_TIMEOUT) { wait_thread.value }
      rescue Timeout::Error
        terminate_process(wait_thread)
        raise Timeout::Error, "production db:prepare exceeded #{PREPARE_TIMEOUT} seconds"
      end

      [ stdout_reader.value, stderr_reader.value, status ]
    ensure
      stdout_reader&.join(1)
      stderr_reader&.join(1)
    end
  end

  def terminate_process(wait_thread)
    Process.kill("TERM", wait_thread.pid)
    Timeout.timeout(5) { wait_thread.value }
  rescue Errno::ESRCH
    nil
  rescue Timeout::Error
    Process.kill("KILL", wait_thread.pid)
    wait_thread.value
  end

  def sanitized_process_failure(stdout, stderr)
    output = [ stdout, stderr ].reject(&:blank?).join("\n")
    password = connection_config[:password].to_s
    if password.present?
      [ password, CGI.escapeURIComponent(password) ].uniq.each do |value|
        output = output.gsub(value, "[FILTERED]")
      end
    end
    "production db:prepare failed:\n#{output}"
  end

  def drop_database(database)
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL)
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = #{connection.quote(database)}
        AND pid <> pg_backend_pid()
    SQL
    connection.execute("DROP DATABASE IF EXISTS #{connection.quote_table_name(database)}")
  end
end
