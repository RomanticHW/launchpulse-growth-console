require "rails_helper"

RSpec.describe "Public request idempotency" do
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  def published_contact_form(slug:)
    site = create(:site, slug:, status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", key: "email", field_type: "email", required: true, position: 0)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    [ site, form, section ]
  end

  def published_product(slug:)
    site = create(:site, slug:, status: "published")
    page = create(:page, site:)
    section = create(
      :section,
      page:,
      kind: "product_grid",
      props: { "products" => [ { "name" => "Calm Cream", "product_key" => "calm-cream", "price" => "$28" } ] }
    )
    product = site.products.create!(name: "Calm Cream", key: "calm-cream", description: "Demo", price: 28)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    [ site, product, section ]
  end

  def published_plan(slug:)
    site = create(:site, slug:, status: "published")
    page = create(:page, site:)
    section = create(
      :section,
      page:,
      kind: "pricing",
      props: { "plans" => [ { "name" => "Cohort", "plan_key" => "cohort", "price" => "$399" } ] }
    )
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    [ site, section ]
  end

  def capture_record_not_unique
    ActiveRecord::Base.transaction(requires_new: true) { yield }
    raise "expected a database unique violation"
  rescue ActiveRecord::RecordNotUnique => error
    error
  end

  def postgres_constraint_name(error)
    error.cause.result.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME)
  end

  it "replays a contact submission without duplicating records, events, or jobs" do
    site, form = published_contact_form(slug: "contact-idempotency-demo")
    request_token = SecureRandom.uuid
    request_params = {
      request_token:,
      form_submission: { email: "lead@example.test" }
    }
    path = "/s/contact-idempotency-demo/forms/#{form.id}/submissions"

    expect { post path, params: request_params }.to have_enqueued_job(AggregateEventJob).once
    expect(response).to redirect_to("/s/contact-idempotency-demo?submitted=1")
    expect { post path, params: request_params }.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to redirect_to("/s/contact-idempotency-demo?submitted=1")
    expect(site.contacts.count).to eq(1)
    expect(form.form_submissions.count).to eq(1)
    expect(site.events.where(event_type: "form_submit").count).to eq(1)
  end

  it "creates separate contact submissions for different request tokens" do
    site, form = published_contact_form(slug: "contact-distinct-token-demo")
    path = "/s/contact-distinct-token-demo/forms/#{form.id}/submissions"

    post path, params: { request_token: SecureRandom.uuid, form_submission: { email: "lead@example.test" } }
    post path, params: { request_token: SecureRandom.uuid, form_submission: { email: "lead@example.test" } }

    expect(site.contacts.count).to eq(1)
    expect(form.form_submissions.count).to eq(2)
    expect(site.events.where(event_type: "form_submit").count).to eq(2)
  end

  it "keeps repeated contact submissions without a token backward compatible" do
    site, form = published_contact_form(slug: "contact-legacy-demo")
    path = "/s/contact-legacy-demo/forms/#{form.id}/submissions"

    post path, params: { form_submission: { email: "first@example.test" } }
    post path, params: { form_submission: { email: "second@example.test" } }

    expect(site.contacts.count).to eq(2)
    expect(form.form_submissions.count).to eq(2)
    expect(site.events.where(event_type: "form_submit").count).to eq(2)
  end

  it "rejects an invalid contact request token without writing business records" do
    site, form = published_contact_form(slug: "contact-invalid-token-demo")
    path = "/s/contact-invalid-token-demo/forms/#{form.id}/submissions"

    expect do
      post path, params: { request_token: "not-a-uuid", form_submission: { email: "lead@example.test" } }
    end.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.contacts.count).to eq(0)
    expect(form.form_submissions.count).to eq(0)
    expect(site.events.count).to eq(0)
  end

  it "treats a form request token constraint race as success when the scoped submission exists" do
    site, form = published_contact_form(slug: "contact-race-demo")
    request_token = SecureRandom.uuid
    contact = site.contacts.create!(email: "lead@example.test", source: "public_site")
    existing_submission = form.form_submissions.create!(
      contact:,
      payload: { "email" => contact.email },
      request_token:
    )
    request_token_error = capture_record_not_unique do
      duplicate = form.form_submissions.build(payload: { "email" => contact.email }, request_token:)
      duplicate.save!(validate: false)
    end
    expect(postgres_constraint_name(request_token_error)).to eq("idx_form_submissions_unique_request_token")
    allow_any_instance_of(Public::FormSubmissionsController).to receive(:find_site).and_return(site)
    allow(site.forms).to receive(:find).and_return(form)
    allow(form.form_submissions).to receive(:create!).and_raise(request_token_error)
    allow_any_instance_of(Public::FormSubmissionsController)
      .to receive(:find_submission_by_request_token)
      .and_return(nil, existing_submission)

    expect do
      post "/s/contact-race-demo/forms/#{form.id}/submissions", params: {
        request_token:,
        form_submission: { email: contact.email }
      }
    end.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to redirect_to("/s/contact-race-demo?submitted=1")
    expect(form.form_submissions.count).to eq(1)
    expect(site.events.count).to eq(0)
  end

  it "does not swallow a contact email constraint violation when the request token already exists" do
    site, form = published_contact_form(slug: "contact-unrelated-race-demo")
    request_token = SecureRandom.uuid
    contact = site.contacts.create!(email: "lead@example.test", source: "public_site")
    existing_submission = form.form_submissions.create!(
      contact:,
      payload: { "email" => contact.email },
      request_token:
    )
    contact_error = capture_record_not_unique do
      duplicate = site.contacts.build(email: contact.email, source: "public_site")
      duplicate.save!(validate: false)
    end
    expect(postgres_constraint_name(contact_error)).to eq("index_contacts_on_site_id_and_email")
    allow_any_instance_of(Public::FormSubmissionsController).to receive(:find_site).and_return(site)
    allow(site.forms).to receive(:find).and_return(form)
    allow(site.contacts).to receive(:find_or_create_by!).and_raise(contact_error)
    allow_any_instance_of(Public::FormSubmissionsController)
      .to receive(:find_submission_by_request_token)
      .and_return(nil, existing_submission)

    expect do
      post "/s/contact-unrelated-race-demo/forms/#{form.id}/submissions", params: {
        request_token:,
        form_submission: { email: contact.email }
      }
    end.to raise_error(ActiveRecord::RecordNotUnique) { |error| expect(error).to equal(contact_error) }

    expect(form.form_submissions.count).to eq(1)
    expect(site.events.count).to eq(0)
  end

  it "replays a product checkout without duplicating orders, items, events, or jobs" do
    site, _product, section = published_product(slug: "product-idempotency-demo")
    request_params = { section_uid: section.uid, request_token: SecureRandom.uuid }
    path = "/s/product-idempotency-demo/products/calm-cream/checkout"

    expect { post path, params: request_params }.to have_enqueued_job(AggregateEventJob).exactly(2).times
    expect(response).to redirect_to("/s/product-idempotency-demo?ordered=1")
    expect { post path, params: request_params }.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to redirect_to("/s/product-idempotency-demo?ordered=1")
    expect(site.orders.count).to eq(1)
    expect(site.orders.first.order_items.count).to eq(1)
    expect(site.events.where(event_type: "checkout_click").count).to eq(1)
    expect(site.events.where(event_type: "order_created").count).to eq(1)
  end

  it "creates separate product orders for different request tokens" do
    site, _product, section = published_product(slug: "product-distinct-token-demo")
    path = "/s/product-distinct-token-demo/products/calm-cream/checkout"

    post path, params: { section_uid: section.uid, request_token: SecureRandom.uuid }
    post path, params: { section_uid: section.uid, request_token: SecureRandom.uuid }

    expect(site.orders.count).to eq(2)
    expect(OrderItem.where(order: site.orders).count).to eq(2)
    expect(site.events.where(event_type: "checkout_click").count).to eq(2)
    expect(site.events.where(event_type: "order_created").count).to eq(2)
  end

  it "rejects an invalid product request token before creating an assignment or order" do
    site, _product, section = published_product(slug: "product-invalid-token-demo")
    experiment = create(:experiment, site:, section: Section.find_by!(uid: section.uid), primary_goal: "order_created")
    create(:variant, experiment:, key: "variant", name: "Variant")
    path = "/s/product-invalid-token-demo/products/calm-cream/checkout"

    expect do
      post path, params: { section_uid: section.uid, request_token: "x" * 101 }
    end.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.orders.count).to eq(0)
    expect(site.events.count).to eq(0)
    expect(experiment.assignments.count).to eq(0)
  end

  it "replays a pricing checkout without duplicating orders, events, or jobs" do
    site, section = published_plan(slug: "pricing-idempotency-demo")
    request_params = { section_uid: section.uid, request_token: SecureRandom.uuid }
    path = "/s/pricing-idempotency-demo/plans/cohort/checkout"

    expect { post path, params: request_params }.to have_enqueued_job(AggregateEventJob).exactly(2).times
    expect(response).to redirect_to("/s/pricing-idempotency-demo?ordered=1")
    expect { post path, params: request_params }.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to redirect_to("/s/pricing-idempotency-demo?ordered=1")
    expect(site.orders.count).to eq(1)
    expect(site.events.where(event_type: "checkout_click").count).to eq(1)
    expect(site.events.where(event_type: "order_created").count).to eq(1)
  end

  it "rejects an invalid pricing request token without writing business records" do
    site, section = published_plan(slug: "pricing-invalid-token-demo")
    path = "/s/pricing-invalid-token-demo/plans/cohort/checkout"

    expect do
      post path, params: { section_uid: section.uid, request_token: "not-a-uuid" }
    end.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.orders.count).to eq(0)
    expect(site.events.count).to eq(0)
  end

  it "treats a product order unique race as success only after the scoped order exists" do
    site, _product, section = published_product(slug: "product-race-demo")
    request_token = SecureRandom.uuid
    existing_order = site.orders.create!(
      number: "ORD-RACE",
      email: "buyer@example.test",
      total: 28,
      source: "public_checkout",
      request_token:
    )
    request_token_error = capture_record_not_unique do
      duplicate = site.orders.build(
        number: "ORD-OTHER",
        email: "other@example.test",
        total: 28,
        source: "public_checkout",
        request_token:
      )
      duplicate.save!(validate: false)
    end
    expect(postgres_constraint_name(request_token_error)).to eq("idx_orders_unique_request_token")
    allow_any_instance_of(Public::CheckoutsController)
      .to receive(:find_order_by_request_token)
      .and_return(nil, existing_order)
    allow_any_instance_of(Public::CheckoutsController)
      .to receive(:create_product_order!)
      .and_raise(request_token_error)

    expect do
      post "/s/product-race-demo/products/calm-cream/checkout", params: {
        section_uid: section.uid,
        request_token:
      }
    end.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to redirect_to("/s/product-race-demo?ordered=1")
    expect(site.orders.count).to eq(1)
    expect(site.events.count).to eq(0)
  end

  it "does not swallow an order number constraint violation when the request token already exists" do
    site, _product, section = published_product(slug: "product-unrelated-race-demo")
    request_token = SecureRandom.uuid
    existing_order = site.orders.create!(
      number: "ORD-RACE",
      email: "buyer@example.test",
      total: 28,
      source: "public_checkout",
      request_token:
    )
    order_number_error = capture_record_not_unique do
      duplicate = site.orders.build(
        number: existing_order.number,
        email: "other@example.test",
        total: 28,
        source: "public_checkout",
        request_token: SecureRandom.uuid
      )
      duplicate.save!(validate: false)
    end
    expect(postgres_constraint_name(order_number_error)).to eq("index_orders_on_site_id_and_number")
    allow_any_instance_of(Public::CheckoutsController)
      .to receive(:find_order_by_request_token)
      .and_return(nil, existing_order)
    allow_any_instance_of(Public::CheckoutsController)
      .to receive(:create_product_order!)
      .and_raise(order_number_error)

    expect do
      post "/s/product-unrelated-race-demo/products/calm-cream/checkout", params: {
        section_uid: section.uid,
        request_token:
      }
    end.to raise_error(ActiveRecord::RecordNotUnique) { |error| expect(error).to equal(order_number_error) }

    expect(site.orders.count).to eq(1)
    expect(site.events.count).to eq(0)
  end

  it "fails closed when a unique violation has no PostgreSQL constraint information" do
    site, _product, section = published_product(slug: "product-unknown-race-demo")
    request_token = SecureRandom.uuid
    existing_order = site.orders.create!(
      number: "ORD-RACE",
      email: "buyer@example.test",
      total: 28,
      source: "public_checkout",
      request_token:
    )
    unknown_error = ActiveRecord::RecordNotUnique.new("constraint unavailable")
    allow_any_instance_of(Public::CheckoutsController)
      .to receive(:find_order_by_request_token)
      .and_return(nil, existing_order)
    allow_any_instance_of(Public::CheckoutsController)
      .to receive(:create_product_order!)
      .and_raise(unknown_error)

    expect do
      post "/s/product-unknown-race-demo/products/calm-cream/checkout", params: {
        section_uid: section.uid,
        request_token:
      }
    end.to raise_error(ActiveRecord::RecordNotUnique) { |error| expect(error).to equal(unknown_error) }

    expect(site.orders.count).to eq(1)
    expect(site.events.count).to eq(0)
  end

  it "renders a top-level UUID request token for each public form and checkout button" do
    site = create(:site, slug: "request-token-view-demo", status: "published")
    page = create(:page, site:)
    contact_section = create(:section, page:, kind: "contact_form", position: 0)
    form = site.forms.create!(section: contact_section, name: "Lead form")
    form.form_fields.create!(label: "Email", key: "email", field_type: "email", required: true, position: 0)
    create(
      :section,
      page:,
      kind: "product_grid",
      position: 1,
      props: { "products" => [ { "name" => "Calm Cream", "product_key" => "calm-cream", "price" => "$28" } ] }
    )
    create(
      :section,
      page:,
      kind: "pricing",
      position: 2,
      props: { "plans" => [ { "name" => "Cohort", "plan_key" => "cohort", "price" => "$399" } ] }
    )
    site.products.create!(name: "Calm Cream", key: "calm-cream", description: "Demo", price: 28)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    get "/s/request-token-view-demo"

    document = Nokogiri::HTML(response.body)
    token_inputs = document.css('form input[name="request_token"]')
    expect(token_inputs.size).to eq(3)
    expect(token_inputs.map { |input| input["value"] }).to all(match(UUID_PATTERN))
    expect(token_inputs.map { |input| input["value"] }.uniq.size).to eq(3)
    contact_form = document.at_css("form[action='/s/request-token-view-demo/forms/#{form.id}/submissions']")
    expect(contact_form.at_css('input[name="form_submission[request_token]"]')).to be_nil
  end
end
