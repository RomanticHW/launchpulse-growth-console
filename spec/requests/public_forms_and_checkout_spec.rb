require "rails_helper"

RSpec.describe "Public forms and checkout" do
  it "renders dynamic form fields and stores submitted payload" do
    site = create(:site, slug: "dynamic-form-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    experiment = create(:experiment, site:, section:, primary_goal: "form_submit")
    create(:variant, experiment:, key: "variant", name: "Variant")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", field_type: "email", required: true, position: 0)
    form.form_fields.create!(label: "Headcount", field_type: "text", required: true, position: 1)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    get "/s/dynamic-form-demo"
    expect(response.body).to include("Headcount")

    post "/s/dynamic-form-demo/forms/#{form.id}/submissions", params: {
      form_submission: { email: "lead@example.test", headcount: "12" }
    }

    expect(response).to redirect_to("/s/dynamic-form-demo?submitted=1")
    expect(form.form_submissions.last.payload).to include("email" => "lead@example.test", "headcount" => "12")
    event = site.events.where(event_type: "form_submit").last
    expect(event.experiment).to eq(experiment)
    expect(experiment.assignments.find_by(visitor_id: event.visitor_id)).to be_present
  end

  it "attributes form submission to a paused experiment when the visitor was already assigned" do
    site = create(:site, slug: "paused-form-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    experiment = create(:experiment, site:, section:, primary_goal: "form_submit")
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", key: "email", field_type: "email", required: true, position: 0)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    get "/s/paused-form-demo"
    visitor = experiment.assignments.last.visitor_id
    expect(visitor).to be_present

    experiment.update!(status: "paused")

    post "/s/paused-form-demo/forms/#{form.id}/submissions", params: {
      form_submission: { email: "lead@example.test" }
    }

    expect(response).to redirect_to("/s/paused-form-demo?submitted=1")
    event = site.events.where(event_type: "form_submit").last
    expect(event.experiment).to eq(experiment)
    expect(event.variant).to eq(variant)

    perform_enqueued_jobs
    expect(experiment.assignments.find_by!(visitor_id: visitor).conversions.where(conversion_type: "form_submit").count).to eq(1)
  end


  it "rejects missing required dynamic fields" do
    site = create(:site, slug: "required-form-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", field_type: "email", required: true, position: 0)
    form.form_fields.create!(label: "Goal", field_type: "text", required: true, position: 1)

    post "/s/required-form-demo/forms/#{form.id}/submissions", params: {
      form_submission: { email: "lead@example.test" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(form.form_submissions.count).to eq(0)
  end

  it "returns a validation error when form_submission is missing" do
    site = create(:site, slug: "missing-form-payload-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", key: "email", field_type: "email", required: true, position: 0)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/missing-form-payload-demo/forms/#{form.id}/submissions", params: {}

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("请填写邮箱")
    expect(site.contacts.count).to eq(0)
    expect(form.form_submissions.count).to eq(0)
  end

  it "rejects string form_submission payloads" do
    site = create(:site, slug: "string-form-payload-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", key: "email", field_type: "email", required: true, position: 0)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/string-form-payload-demo/forms/#{form.id}/submissions",
      params: { form_submission: "not-an-object" },
      as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("表单内容格式不正确")
    expect(site.contacts.count).to eq(0)
    expect(form.form_submissions.count).to eq(0)
  end

  it "rejects array form_submission payloads" do
    site = create(:site, slug: "array-form-payload-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", key: "email", field_type: "email", required: true, position: 0)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/array-form-payload-demo/forms/#{form.id}/submissions",
      params: { form_submission: [ "email", "lead@example.test" ] },
      as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("表单内容格式不正确")
    expect(site.contacts.count).to eq(0)
    expect(form.form_submissions.count).to eq(0)
  end

  it "creates a demo order and attributed order_created event from product checkout" do
    site = create(:site, slug: "checkout-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "product_grid", props: { "headline" => "Products", "products" => [ { "name" => "Calm Cream", "price" => "$28" } ] })
    product = site.products.create!(name: "Calm Cream", description: "Demo", price: 28)
    experiment = create(:experiment, site:, section:, primary_goal: "order_created")
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/checkout-demo/products/calm-cream/checkout", params: { section_uid: section.uid }

    expect(response).to redirect_to("/s/checkout-demo?ordered=1")
    expect(site.orders.last.order_items.last.product).to eq(product)
    event = site.events.where(event_type: "order_created").last
    expect(event.experiment).to eq(experiment)
    Analytics::AggregationService.new(event).call
    expect(experiment.assignments.find_by(visitor_id: event.visitor_id).variant).to eq(variant)
    expect(experiment.conversions.where(conversion_type: "order_created").count).to eq(1)
  end

  it "shows a confirmation after checkout redirects back to the public page" do
    site = create(:site, slug: "checkout-confirmation-demo", status: "published")
    page = create(:page, site:)
    create(:section, page:, kind: "product_grid", props: { "products" => [ { "name" => "Calm Cream", "product_key" => "calm-cream", "price" => "$28" } ] })
    site.products.create!(name: "Calm Cream", key: "calm-cream", description: "Demo", price: 28)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    get "/s/checkout-confirmation-demo", params: { ordered: 1 }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("订单已创建")
  end

  it "sanitizes section and product metadata through the shared sanitizer" do
    site = create(:site, slug: "checkout-metadata-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "product_grid", props: { "products" => [ { "name" => "Calm Cream", "product_key" => "calm-cream" } ] })
    site.products.create!(name: "Calm Cream", key: "calm-cream", description: "Demo", price: 28)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/checkout-metadata-demo/products/calm-cream/checkout", params: { section_uid: section.uid }

    event = site.events.where(event_type: "order_created").last
    expect(event.metadata).to include("section_uid" => section.uid, "product_key" => "calm-cream")
  end

  it "rejects oversized public tracking identifiers after metadata merge" do
    site = create(:site, slug: "public-large-metadata-demo", status: "published")
    page = create(:page, site:)
    create(:section, page:)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/public-large-metadata-demo/events", params: {
      event_type: "product_view",
      product_key: "x" * 5.kilobytes
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.events.count).to eq(0)
  end

  it "rejects top-level array metadata for public tracking events" do
    site = create(:site, slug: "public-array-metadata-demo", status: "published")
    page = create(:page, site:)
    create(:section, page:)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/public-array-metadata-demo/events", params: {
      event_type: "product_view",
      metadata: [ "campaign", "spring" ]
    }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.events.count).to eq(0)
  end

  it "keeps nested array metadata for public tracking events" do
    site = create(:site, slug: "public-nested-metadata-demo", status: "published")
    page = create(:page, site:)
    create(:section, page:)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/public-nested-metadata-demo/events", params: {
      event_type: "product_view",
      metadata: { campaign: { tags: [ "spring", "vip" ] } }
    }, as: :json

    expect(response).to have_http_status(:accepted)
    expect(site.events.last.metadata).to include("campaign" => { "tags" => [ "spring", "vip" ] })
  end

  it "rolls back product checkout when event recording fails" do
    site = create(:site, slug: "checkout-rollback-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "product_grid", props: { "products" => [ { "name" => "Calm Cream", "product_key" => "calm-cream" } ] })
    site.products.create!(name: "Calm Cream", key: "calm-cream", description: "Demo", price: 28)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    allow_any_instance_of(Public::CheckoutsController)
      .to receive(:record_public_event!)
      .and_raise(Events::MetadataSanitizer::InvalidMetadata, "event failed")

    post "/s/checkout-rollback-demo/products/calm-cream/checkout", params: { section_uid: section.uid }

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.orders.count).to eq(0)
    expect(site.events.count).to eq(0)
  end

  it "rejects product checkout when section uid is not a product grid" do
    site = create(:site, slug: "wrong-product-section-demo", status: "published")
    page = create(:page, site:)
    hero = create(:section, page:, kind: "hero")
    site.products.create!(name: "Calm Cream", key: "calm-cream", description: "Demo", price: 28)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/wrong-product-section-demo/products/calm-cream/checkout", params: { section_uid: hero.uid }

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.orders.count).to eq(0)
  end

  it "rejects product checkout when product key is absent from published section props" do
    site = create(:site, slug: "missing-product-props-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "product_grid", props: { "products" => [ { "name" => "Other Cream", "product_key" => "other-cream" } ] })
    site.products.create!(name: "Calm Cream", key: "calm-cream", description: "Demo", price: 28)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/missing-product-props-demo/products/calm-cream/checkout", params: { section_uid: section.uid }

    expect(response).to have_http_status(:not_found)
    expect(site.orders.count).to eq(0)
  end

  it "rejects product checkout when product is inactive" do
    site = create(:site, slug: "inactive-product-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "product_grid", props: { "products" => [ { "name" => "Calm Cream", "product_key" => "calm-cream" } ] })
    site.products.create!(name: "Calm Cream", key: "calm-cream", description: "Demo", price: 28, active: false)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/inactive-product-demo/products/calm-cream/checkout", params: { section_uid: section.uid }

    expect(response).to have_http_status(:not_found)
    expect(site.orders.count).to eq(0)
  end

  it "uses stable product keys when product display names change" do
    site = create(:site, slug: "product-key-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "product_grid", props: { "headline" => "Products", "products" => [ { "name" => "Calm Cream", "price" => "$28", "product_key" => "calm-cream" } ] })
    product = site.products.create!(name: "New Calm Cream", key: "calm-cream", description: "Demo", price: 28)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/product-key-demo/products/calm-cream/checkout", params: { section_uid: section.uid }

    expect(response).to redirect_to("/s/product-key-demo?ordered=1")
    expect(site.orders.last.order_items.last.product).to eq(product)
  end

  it "creates a demo order and order_created event from pricing checkout" do
    site = create(:site, slug: "pricing-checkout-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "pricing", props: { "headline" => "Plans", "plans" => [ { "name" => "Cohort", "price" => "$399", "description" => "Live calls" } ] })
    experiment = create(:experiment, site:, section:, primary_goal: "order_created")
    create(:variant, experiment:, key: "variant", name: "Variant")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/pricing-checkout-demo/plans/cohort/checkout", params: { section_uid: section.uid }

    expect(response).to redirect_to("/s/pricing-checkout-demo?ordered=1")
    expect(site.orders.last.source).to eq("public_pricing_checkout")
    event = site.events.where(event_type: "order_created").last
    expect(event.experiment).to eq(experiment)
  end

  it "rolls back pricing checkout when event recording fails" do
    site = create(:site, slug: "pricing-rollback-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "pricing", props: { "plans" => [ { "name" => "Cohort", "price" => "$399" } ] })
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    allow_any_instance_of(Public::CheckoutsController)
      .to receive(:record_public_event!)
      .and_raise(Events::MetadataSanitizer::InvalidMetadata, "event failed")

    post "/s/pricing-rollback-demo/plans/cohort/checkout", params: { section_uid: section.uid }

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.orders.count).to eq(0)
    expect(site.events.count).to eq(0)
  end

  it "rejects pricing checkout when section uid is not pricing" do
    site = create(:site, slug: "wrong-pricing-section-demo", status: "published")
    page = create(:page, site:)
    hero = create(:section, page:, kind: "hero")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/wrong-pricing-section-demo/plans/cohort/checkout", params: { section_uid: hero.uid }

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.orders.count).to eq(0)
  end

  it "rejects product checkout for hidden sections" do
    site = create(:site, slug: "hidden-checkout-demo", status: "published")
    page = create(:page, site:)
    create(:section, page:, kind: "hero", position: 0)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    hidden_section = create(:section, page:, kind: "product_grid", position: 1)
    site.products.create!(name: "Calm Cream", key: "calm-cream", description: "Demo", price: 28)

    post "/s/hidden-checkout-demo/products/calm-cream/checkout", params: { section_uid: hidden_section.uid }

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.orders.count).to eq(0)
  end

  it "returns 422 for invalid public form email without creating records" do
    site = create(:site, slug: "bad-email-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", key: "email", field_type: "email", required: true, position: 0)

    post "/s/bad-email-demo/forms/#{form.id}/submissions", params: {
      form_submission: { email: "bad-email" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.contacts.count).to eq(0)
    expect(form.form_submissions.count).to eq(0)
    expect(site.events.count).to eq(0)
  end

  it "rolls back contact and form submission when form_submit event creation fails" do
    site = create(:site, slug: "form-event-rollback-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", key: "email", field_type: "email", required: true, position: 0)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    allow_any_instance_of(Public::FormSubmissionsController)
      .to receive(:record_public_event!)
      .and_raise(Events::MetadataSanitizer::InvalidMetadata, "event failed")

    post "/s/form-event-rollback-demo/forms/#{form.id}/submissions", params: {
      form_submission: { email: "lead@example.test" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.contacts.count).to eq(0)
    expect(form.form_submissions.count).to eq(0)
    expect(site.events.count).to eq(0)
  end

  it "stores form event metadata after sanitizer merges form and section identifiers" do
    site = create(:site, slug: "form-metadata-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", key: "email", field_type: "email", required: true, position: 0)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/s/form-metadata-demo/forms/#{form.id}/submissions", params: {
      form_submission: { email: "lead@example.test" }
    }

    event = site.events.where(event_type: "form_submit").last
    expect(event.metadata).to include("form_id" => form.id, "section_uid" => section.uid)
  end

  it "keeps submitted payload keys stable when form labels change" do
    site = create(:site, slug: "stable-form-key-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email address", key: "email", field_type: "email", required: true, position: 0)
    form.form_fields.create!(label: "Team size", key: "headcount", field_type: "text", required: true, position: 1)

    form.form_fields.find_by!(key: "headcount").update!(label: "Number of people")
    post "/s/stable-form-key-demo/forms/#{form.id}/submissions", params: {
      form_submission: { email: "lead@example.test", headcount: "12" }
    }

    expect(response).to redirect_to("/s/stable-form-key-demo?submitted=1")
    expect(form.form_submissions.last.payload).to include("headcount" => "12")
  end
end
