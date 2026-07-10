require "rails_helper"
require "timeout"

RSpec.describe "Site token rotation concurrency" do
  self.use_transactional_tests = false

  after do
    @account&.destroy!
    @user&.destroy!
  end

  it "serializes two rotations so only the final demo key remains active" do
    @account = create(:account)
    @user = create(:user, email: "rotation-#{SecureRandom.hex(8)}@example.test", password: "password")
    create(:membership, account: @account, user: @user)
    site = create(:site, account: @account)
    old_key, = ApiKey.issue!(site:, name: "Demo tracking token")
    create(:page, site:)
    sessions = 2.times.map do
      ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
        session.post("/session", params: { email: @user.email, password: "password" })
        raise "sign in failed" unless session.response.redirect?
      end
    end
    Rails.application.reload_routes!
    first_inside_lock = Queue.new
    release_first = Queue.new
    results = Queue.new
    first_call = true
    call_mutex = Mutex.new
    allow(ApiKey).to receive(:issue!).and_wrap_original do |original, **arguments|
      gated = call_mutex.synchronize do
        next false unless first_call

        first_call = false
        true
      end
      if gated
        first_inside_lock << true
        release_first.pop
      end
      original.call(**arguments)
    end

    first_thread = rotation_thread(sessions.first, site, results)
    Timeout.timeout(5) { first_inside_lock.pop }
    second_thread = rotation_thread(sessions.second, site, results)
    expect { Timeout.timeout(0.3) { results.pop } }.to raise_error(Timeout::Error)

    release_first << true
    responses = 2.times.map { Timeout.timeout(10) { results.pop } }
    Timeout.timeout(10) do
      first_thread.join
      second_thread.join
    end

    expect(responses.map(&:first)).to contain_exactly(302, 302)
    expect(responses.map(&:last).uniq.size).to eq(2)
    expect(old_key.reload).not_to be_active
    expect(site.api_keys.where(name: "Demo tracking token").count).to eq(3)
    expect(site.api_keys.active.where(name: "Demo tracking token").count).to eq(1)
  ensure
    release_first << true if first_thread&.alive?
    [ first_thread, second_thread ].compact.each do |thread|
      thread.kill if thread.alive?
      thread.join(1)
    end
  end

  private

  def rotation_thread(session, site, results)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        backend_pid = connection.select_value("SELECT pg_backend_pid()")
        session.post("/sites/#{site.id}/rotate_tracking_token")
        results << [ session.response.status, nil, backend_pid ]
      rescue StandardError => error
        results << [ :error, error, backend_pid ]
      end
    end
  end
end
