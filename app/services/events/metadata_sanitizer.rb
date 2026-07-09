module Events
  class MetadataSanitizer
    InvalidMetadata = Class.new(StandardError)
    MAX_DEPTH = 5
    MAX_KEYS = 50

    def initialize(value, limit_bytes: Events::IngestionService::METADATA_LIMIT_BYTES, require_hash_root: true)
      @value = value
      @limit_bytes = limit_bytes
      @require_hash_root = require_hash_root
    end

    def call
      raise InvalidMetadata, "metadata must be an object" if @require_hash_root && !hash_like?(@value)

      sanitized = sanitize(@value, depth: 0)
      # 附加数据来自公开页面或外部接口，先限制体积和深度，比等到数据库序列化失败更可控。
      raise InvalidMetadata, "metadata is too large" if sanitized.to_json.bytesize > @limit_bytes

      sanitized
    end

    private

    def hash_like?(value)
      value.is_a?(Hash) || value.is_a?(ActionController::Parameters)
    end

    def sanitize(value, depth:)
      raise InvalidMetadata, "metadata is too deep" if depth > MAX_DEPTH

      case value
      when ActionController::Parameters
        sanitize_hash(value.to_unsafe_h, depth:)
      when Hash
        sanitize_hash(value, depth:)
      when Array
        value.map { |nested_value| sanitize(nested_value, depth: depth + 1) }
      when String, Numeric, TrueClass, FalseClass, NilClass
        value
      else
        value.to_s
      end
    end

    def sanitize_hash(value, depth:)
      raise InvalidMetadata, "metadata has too many keys" if value.size > MAX_KEYS

      value.each_with_object({}) do |(key, nested_value), result|
        result[key.to_s] = sanitize(nested_value, depth: depth + 1)
      end
    end
  end
end
