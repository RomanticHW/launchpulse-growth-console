require "uri"

module DatabaseUrlConfig
  ERROR_MESSAGE = "Database URL must be a valid PostgreSQL URL with a database path"
  URL_KEYS = %w[DATABASE_URL CACHE_DATABASE_URL QUEUE_DATABASE_URL CABLE_DATABASE_URL].freeze
  POSTGRES_SCHEMES = %w[postgres postgresql].freeze

  module_function

  def validate_environment!(environment = ENV)
    URL_KEYS.each { |key| parse(environment[key]) }
  end

  def parse(database_url)
    return if database_url.nil? || database_url.empty?

    uri = URI.parse(database_url)
    valid_scheme = POSTGRES_SCHEMES.include?(uri.scheme)
    valid_path = uri.path && !uri.path.empty? && uri.path != "/"
    raise ArgumentError unless valid_scheme && valid_path && !uri.opaque

    uri
  rescue StandardError
    raise ArgumentError, ERROR_MESSAGE, cause: nil
  end

  def derive(database_uri, suffix)
    return unless database_uri

    uri = database_uri.dup
    uri.path = "#{uri.path}_#{suffix}"
    uri
  rescue StandardError
    raise ArgumentError, ERROR_MESSAGE, cause: nil
  end
end
