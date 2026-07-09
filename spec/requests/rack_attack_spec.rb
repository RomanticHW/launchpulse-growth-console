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
end
