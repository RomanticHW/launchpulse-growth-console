require "digest"

module PublicRequests
  class Fingerprint
    def self.call(operation:, attributes:)
      canonical_payload = Events::PayloadFingerprint.normalize(
        "operation" => operation,
        "attributes" => attributes
      )
      Digest::SHA256.hexdigest(JSON.generate(canonical_payload))
    end
  end
end
