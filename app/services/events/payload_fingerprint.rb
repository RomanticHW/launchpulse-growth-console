require "digest"

module Events
  class PayloadFingerprint
    FIELDS = %i[event_type visitor_id session_id source device page_path section_uid experiment_id variant_key occurred_at metadata].freeze

    def self.call(params)
      normalized = FIELDS.each_with_object({}) do |field, result|
        value = params[field]
        next if skippable?(value)

        result[field.to_s] = field == :occurred_at ? normalize_time(value) : normalize(value)
      end
      Digest::SHA256.hexdigest(JSON.generate(normalized.sort.to_h))
    end

    def self.normalize(value)
      case value
      when ActionController::Parameters
        normalize(value.to_unsafe_h)
      when Hash
        value.transform_keys(&:to_s).sort.to_h { |key, nested| [ key, normalize(nested) ] }
      when Array
        value.map { |nested| normalize(nested) }
      when String, Numeric, TrueClass, FalseClass, NilClass
        value
      when Time, DateTime, ActiveSupport::TimeWithZone
        value.iso8601(6)
      else
        value.to_s
      end
    end

    def self.normalize_time(value)
      return value.iso8601(6) if value.respond_to?(:iso8601) && !value.is_a?(String)

      parsed = Time.zone.parse(value.to_s)
      parsed ? parsed.iso8601(6) : value.to_s
    rescue ArgumentError, TypeError
      value.to_s
    end

    def self.skippable?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
