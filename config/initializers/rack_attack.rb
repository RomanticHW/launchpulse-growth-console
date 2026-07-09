# frozen_string_literal: true

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

  throttle("public_forms/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{\A/s/[^/]+/forms/}) && req.post?
  end

  throttle("public_checkout/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{\A/s/[^/]+/(products|plans)/}) && req.post?
  end
end
