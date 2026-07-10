require "rails_helper"
require "timeout"

RSpec.describe "Public request concurrency" do
  self.use_transactional_tests = false

  after do
    @site&.destroy!
    @account&.destroy!
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it "serializes identical form requests across two integration sessions" do
    site, form, section = published_contact_form
    request_token = SecureRandom.uuid
    path = "/s/#{site.slug}/forms/#{form.id}/submissions"
    request_params = {
      request_token:,
      section_uid: section.uid,
      form_submission: { email: "lead@example.test" }
    }

    results = post_concurrently([ [ path, request_params ], [ path, request_params ] ])

    expect(results.map(&:first)).to contain_exactly(302, 302), results.inspect
    expect(results.map(&:last).uniq.size).to eq(2)
    expect(site.contacts.count).to eq(1)
    expect(form.form_submissions.count).to eq(1)
    event = site.events.find_by!(event_type: "form_submit")
    expect(aggregate_job_event_ids).to contain_exactly(event.id, event.id)
  end

  it "allows one request and conflicts the other when concurrent payloads share a token" do
    site, form, section = published_contact_form
    request_token = SecureRandom.uuid
    path = "/s/#{site.slug}/forms/#{form.id}/submissions"
    requests = %w[first second].map do |prefix|
      [
        path,
        {
          request_token:,
          section_uid: section.uid,
          form_submission: { email: "#{prefix}@example.test" }
        }
      ]
    end

    results = post_concurrently(requests)

    expect(results.map(&:first)).to contain_exactly(302, 409)
    expect(results.map(&:last).uniq.size).to eq(2)
    expect(site.contacts.count).to eq(1)
    expect(form.form_submissions.count).to eq(1)
    expect(site.events.where(event_type: "form_submit").count).to eq(1)
    expect(aggregate_job_event_ids).to contain_exactly(site.events.find_by!(event_type: "form_submit").id)
  end

  it "recovers concurrent contact creation for the same email with different tokens" do
    site, form, section = published_contact_form
    path = "/s/#{site.slug}/forms/#{form.id}/submissions"
    requests = 2.times.map do
      [
        path,
        {
          request_token: SecureRandom.uuid,
          section_uid: section.uid,
          form_submission: { email: "shared@example.test" }
        }
      ]
    end

    results = post_concurrently(requests)

    expect(results.map(&:first)).to contain_exactly(302, 302)
    expect(results.map(&:last).uniq.size).to eq(2)
    expect(site.contacts.count).to eq(1)
    expect(form.form_submissions.count).to eq(2)
    expect(site.events.where(event_type: "form_submit").count).to eq(2)
    expect(aggregate_job_event_ids.uniq.sort).to eq(site.events.order(:id).pluck(:id).sort)
  end

  it "serializes identical product checkouts across two integration sessions" do
    site, section = published_products
    request_token = SecureRandom.uuid
    path = "/s/#{site.slug}/products/calm-cream/checkout"
    request_params = { request_token:, section_uid: section.uid }

    results = post_concurrently([ [ path, request_params ], [ path, request_params ] ])

    expect(results.map(&:first)).to contain_exactly(302, 302)
    expect(results.map(&:last).uniq.size).to eq(2)
    expect(site.orders.count).to eq(1)
    expect(OrderItem.where(order: site.orders).count).to eq(1)
    expect(site.events.count).to eq(2)
    expect(aggregate_job_event_ids.tally.values).to all(eq(2))
    expect(aggregate_job_event_ids.uniq.sort).to eq(site.events.order(:id).pluck(:id).sort)
  end

  it "allows one checkout and conflicts the other when concurrent product targets share a token" do
    site, section = published_products
    request_token = SecureRandom.uuid
    requests = %w[calm-cream night-cream].map do |product_key|
      [
        "/s/#{site.slug}/products/#{product_key}/checkout",
        { request_token:, section_uid: section.uid }
      ]
    end

    results = post_concurrently(requests)

    expect(results.map(&:first)).to contain_exactly(302, 409)
    expect(results.map(&:last).uniq.size).to eq(2)
    expect(site.orders.count).to eq(1)
    expect(OrderItem.where(order: site.orders).count).to eq(1)
    expect(site.events.count).to eq(2)
    expect(aggregate_job_event_ids.sort).to eq(site.events.order(:id).pluck(:id).sort)
  end

  private

  def published_contact_form
    @site = create(:site, status: "published")
    @account = @site.account
    page = create(:page, site: @site)
    section = create(:section, page:, kind: "contact_form")
    form = @site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", key: "email", field_type: "email", required: true, position: 0)
    Sites::SnapshotService.new(@site).publish!(user: nil, note: "Concurrency spec publish")
    [ @site, form, section ]
  end

  def published_products
    @site = create(:site, status: "published")
    @account = @site.account
    page = create(:page, site: @site)
    section = create(
      :section,
      page:,
      kind: "product_grid",
      props: {
        "products" => [
          { "name" => "Calm Cream", "product_key" => "calm-cream", "price" => "$28" },
          { "name" => "Night Cream", "product_key" => "night-cream", "price" => "$32" }
        ]
      }
    )
    @site.products.create!(name: "Calm Cream", key: "calm-cream", description: "Demo", price: 28)
    @site.products.create!(name: "Night Cream", key: "night-cream", description: "Demo", price: 32)
    Sites::SnapshotService.new(@site).publish!(user: nil, note: "Concurrency spec publish")
    [ @site, section ]
  end

  def post_concurrently(requests)
    Rails.application.reload_routes!
    ready = Queue.new
    release = Queue.new
    results = Queue.new
    threads = requests.map do |path, request_params|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          session = ActionDispatch::Integration::Session.new(Rails.application)
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          ready << true
          release.pop
          session.post(path, params: request_params)
          results << [ session.response.status, session.response.body, backend_pid ]
        rescue StandardError => error
          results << [ :error, error, backend_pid ]
        end
      end
    end

    requests.size.times { Timeout.timeout(5) { ready.pop } }
    requests.size.times { release << true }
    collected = requests.size.times.map { Timeout.timeout(10) { results.pop } }
    Timeout.timeout(10) { threads.each(&:join) }
    errors = collected.select { |result| result.first == :error }
    raise errors.first[1] if errors.any?

    collected
  ensure
    requests.size.times { release << true } if release
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join(1)
    end
  end

  def aggregate_job_event_ids
    enqueued_jobs.filter_map do |job|
      job[:args].first if job[:job] == AggregateEventJob
    end
  end
end
