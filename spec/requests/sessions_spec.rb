require "rails_helper"

RSpec.describe "Sessions" do
  it "resets the session id on successful login" do
    user = create(:user, password: "password")
    create(:membership, user:, account: create(:account))

    get new_session_path
    prior_session = session.id

    post session_path, params: { email: user.email, password: "password" }

    expect(response).to redirect_to(root_path)
    expect(session[:user_id]).to eq(user.id)
    expect(session.id).not_to eq(prior_session) if prior_session.present?
  end
end
