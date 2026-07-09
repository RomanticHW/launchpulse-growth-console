require "rails_helper"

RSpec.describe "Static assets", type: :request do
  it "serves the browser default favicon request" do
    get "/favicon.ico"

    expect(response).to have_http_status(:ok)
    expect(response.body.byteslice(0, 4).bytes).to eq([ 0, 0, 1, 0 ])
  end

  it "keeps public tracking requests alive during navigation" do
    source = Rails.root.join("app/javascript/controllers/public_tracking_controller.js").read

    expect(source).to match(/keepalive:\s*true/)
  end
end
