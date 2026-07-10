require "rails_helper"

RSpec.describe "Rack::Attack throttling" do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    cache = ActiveSupport::Cache::MemoryStore.new
    original = Rack::Attack.cache.store
    Rack::Attack.cache.store = cache
    Rails.cache.clear
    example.run
  ensure
    Rack::Attack.cache.store = original
    Rack::Attack.reset!
  end

  it "returns 429 JSON with Retry-After when login is throttled" do
    10.times do
      post session_path, params: { email: "nobody@example.test", password: "wrong" }
    end

    post session_path, params: { email: "nobody@example.test", password: "wrong" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to be_present
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("rate_limited")
    expect(body["retry_after"]).to be_a(Integer)
  end

  it "uses a stable SHA256 digest instead of the raw API token as discriminator" do
    token = "signed-token-sensitive-value"
    other_token = "different-signed-token"
    throttle = Rack::Attack.throttles.fetch("api_events/token")
    body_request = Rack::Attack::Request.new(
      Rack::MockRequest.env_for(
        "/api/v1/events",
        method: "POST",
        input: Rack::Utils.build_query("site_token" => token),
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      )
    )
    header_request = Rack::Attack::Request.new(
      Rack::MockRequest.env_for("/api/v1/events", method: "POST", "HTTP_X_SITE_TOKEN" => token)
    )
    other_request = Rack::Attack::Request.new(
      Rack::MockRequest.env_for("/api/v1/events", method: "POST", "HTTP_X_SITE_TOKEN" => other_token)
    )

    body_discriminator = throttle.block.call(body_request)
    header_discriminator = throttle.block.call(header_request)
    other_discriminator = throttle.block.call(other_request)

    expect(body_discriminator).to eq(Digest::SHA256.hexdigest(token))
    expect(header_discriminator).to eq(body_discriminator)
    expect(other_discriminator).to eq(Digest::SHA256.hexdigest(other_token))
    expect(other_discriminator).not_to eq(body_discriminator)
    expect(body_discriminator).not_to include(token)
  end

  it "does not create a token discriminator when the API token is absent" do
    throttle = Rack::Attack.throttles.fetch("api_events/token")
    request = Rack::Attack::Request.new(Rack::MockRequest.env_for("/api/v1/events", method: "POST"))

    expect(throttle.block.call(request)).to be_nil
  end

  it "ignores structured and oversized token discriminators" do
    throttle = Rack::Attack.throttles.fetch("api_events/token")
    structured_request = Rack::Attack::Request.new(
      Rack::MockRequest.env_for(
        "/api/v1/events",
        method: "POST",
        input: "site_token[nested]=x",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      )
    )
    oversized_request = Rack::Attack::Request.new(
      Rack::MockRequest.env_for("/api/v1/events", method: "POST", "HTTP_X_SITE_TOKEN" => "x" * (4.kilobytes + 1))
    )

    expect(throttle.block.call(structured_request)).to be_nil
    expect(throttle.block.call(oversized_request)).to be_nil
  end

  it "lets the controller return a normal 4xx for a structured token through the full middleware stack" do
    post "/api/v1/events",
      params: {
        site_token: { nested: "x" },
        event_type: "page_view",
        visitor_id: "visitor-structured-token"
      }

    expect(response).to have_http_status(:unauthorized)
  end
end
