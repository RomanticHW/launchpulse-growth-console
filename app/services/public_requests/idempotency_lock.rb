require "digest"

module PublicRequests
  class IdempotencyLock
    def self.with_lock(scope:, request_token:)
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "SELECT pg_advisory_xact_lock(?)",
            lock_key(scope, request_token)
          ])
        )
        yield
      end
    end

    def self.lock_key(scope, request_token)
      Digest::SHA256.hexdigest("public-request:#{scope}:#{request_token}").first(15).to_i(16)
    end
    private_class_method :lock_key
  end
end
