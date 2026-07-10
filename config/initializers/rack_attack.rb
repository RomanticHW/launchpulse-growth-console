# frozen_string_literal: true

require "digest"

class Rack::Attack
  ### Configure Cache ###
  # Uses Rails.cache; Solid Cache in production.

  ### Throttles ###

  throttle("logins/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/session" && req.post?
  end

  throttle("public_events/ip", limit: 120, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{\A/s/[^/]+/events\z}) && req.post?
  end

  throttle("api_events/ip", limit: 300, period: 1.minute) do |req|
    req.ip if req.path == "/api/v1/events" && req.post?
  end

  # Also key by token when present so one key cannot share another client's IP budget forever.
  throttle("api_events/token", limit: 300, period: 1.minute) do |req|
    next unless req.path == "/api/v1/events" && req.post?

    token = req.params["site_token"].presence || req.get_header("HTTP_X_SITE_TOKEN")
    Digest::SHA256.hexdigest(token) if token.present?
  end

  throttle("public_forms/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{\A/s/[^/]+/forms/}) && req.post?
  end

  throttle("public_checkout/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{\A/s/[^/]+/(products|plans)/}) && req.post?
  end

  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"] || {}
    now = match_data[:epoch_time] || Time.now.to_i
    retry_after = match_data[:period] ? (match_data[:period] - (now % match_data[:period])).to_i : 60
    retry_after = 1 if retry_after <= 0

    headers = {
      "Content-Type" => "application/json; charset=utf-8",
      "Retry-After" => retry_after.to_s
    }
    body = {
      error: "rate_limited",
      message: "请求过于频繁，请稍后重试。",
      retry_after: retry_after
    }.to_json

    [ 429, headers, [ body ] ]
  end
end
