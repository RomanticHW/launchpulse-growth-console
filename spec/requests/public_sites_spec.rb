require "rails_helper"

RSpec.describe "Public sites" do
  def create_published_site(slug:, industry:, sections:)
    site = create(:site, slug:, industry:, status: "published")
    page = create(:page, site:)
    sections.each_with_index do |section_attrs, index|
      create(:section, page:, position: index, **section_attrs)
    end
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    site
  end

  it "rejects a second published site with the same public slug across accounts" do
    account_a = create(:account)
    account_b = create(:account)
    create(:site, account: account_a, slug: "collision-slug", status: "published")

    expect {
      create(:site, account: account_b, slug: "collision-slug", status: "published")
    }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "renders the latest published snapshot instead of unpublished draft sections" do
    site = create(:site, slug: "snapshot-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "hero", props: { "headline" => "Published headline", "subheadline" => "Published body", "cta" => "Start" })
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    section.update!(props: section.props.merge("headline" => "Draft headline"))

    get "/s/snapshot-demo"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Published headline")
    expect(response.body).not_to include("Draft headline")
  end

  it "renders the published site and assigns the visitor to active experiments" do
    site = create(:site, slug: "public-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "hero", props: { "headline" => "Control headline", "subheadline" => "Control body", "cta" => "Start" })
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "control", name: "Control", role: "control", props: section.props)
    create(:variant, experiment:, key: "variant", name: "Variant", props: section.props.merge("headline" => "Variant headline"))
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    get "/s/public-demo"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Control headline").or include("Variant headline")
    expect(experiment.assignments.count).to eq(1)
  end

  it "renders variant props by section uid when snapshot section ids are stale" do
    site = create(:site, slug: "uid-variant-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "hero", props: { "headline" => "Published headline", "subheadline" => "Control body", "cta" => "Start" })
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant", name: "Variant", props: section.props.merge("headline" => "UID variant headline"))
    snapshot = Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    payload = snapshot.payload.deep_dup
    payload["pages"].first["sections"].first["id"] = section.id + 10_000
    snapshot.update!(payload:)

    get "/s/uid-variant-demo"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("UID variant headline")
  end

  it "renders saved control variant props instead of the current published snapshot props" do
    site = create(:site, slug: "control-props-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "hero", props: { "headline" => "Published after patch", "subheadline" => "Changed", "cta" => "Start" })
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "control", name: "Control", role: "control", weight: 100, props: { "headline" => "Original baseline", "subheadline" => "Original", "cta" => "Start" })
    create(:variant, experiment:, key: "variant", name: "Variant", role: "variant", weight: 0, props: { "headline" => "Recommended", "subheadline" => "Changed", "cta" => "Start" })
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    get "/s/control-props-demo"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Original baseline")
    expect(response.body).not_to include("Published after patch")
  end

  it "stores assigned variants on public page views without direct experiment attribution" do
    site = create(:site, slug: "page-view-assignment-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "hero")
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant", name: "Variant")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    get "/s/page-view-assignment-demo"

    event = site.events.find_by!(event_type: "page_view")
    expect(event.experiment_id).to be_nil
    expect(event.variant_id).to be_nil
    expect(event.metadata.fetch("assigned_variants")).to include(experiment.id.to_s)
  end

  it "broadcasts experiment metrics after public page-view assignments" do
    site = create(:site, slug: "page-view-broadcast-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "hero")
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant", name: "Variant")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    broadcaster = instance_spy(Analytics::DashboardBroadcaster)
    allow(Analytics::DashboardBroadcaster).to receive(:new).with(site).and_return(broadcaster)

    get "/s/page-view-broadcast-demo"

    expect(response).to have_http_status(:ok)
    expect(broadcaster).to have_received(:broadcast_experiments)
  end

  it "shows the public runtime debug badge only when demo debug is enabled" do
    site = create(:site, slug: "debug-badge-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "hero")
    experiment = create(:experiment, site:, section:, name: "Hero copy")
    create(:variant, experiment:, key: "variant", name: "Variant")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    get "/s/debug-badge-demo"
    expect(response.body).not_to include("演示运行信息")

    original = ENV["DEMO_DEBUG"]
    ENV["DEMO_DEBUG"] = "true"
    get "/s/debug-badge-demo"

    expect(response.body).to include("演示运行信息")
    expect(response.body).to include("Hero copy: 建议版本")
  ensure
    ENV["DEMO_DEBUG"] = original
  end

  it "renders themed illustrations on public pages" do
    create_published_site(
      slug: "coffee-visual-demo",
      industry: "Local coffee shop",
      sections: [
        { kind: "hero", props: { "headline" => "Coffee", "subheadline" => "Fresh cups", "cta" => "Order" } },
        { kind: "feature_grid", props: { "headline" => "Visit", "items" => [
          { "title" => "Beans", "body" => "Roasted nearby" },
          { "title" => "Pickup", "body" => "Ready fast" },
          { "title" => "Tables", "body" => "Room to work" }
        ] } }
      ]
    )
    create_published_site(
      slug: "course-visual-demo",
      industry: "Online course landing page",
      sections: [
        { kind: "hero", props: { "headline" => "Course", "subheadline" => "Launch faster", "cta" => "Join" } },
        { kind: "feature_grid", props: { "headline" => "Curriculum", "items" => [
          { "title" => "Offer", "body" => "Shape the promise" },
          { "title" => "Page", "body" => "Write the page" },
          { "title" => "Launch", "body" => "Plan the rhythm" }
        ] } }
      ]
    )
    create_published_site(
      slug: "skincare-visual-demo",
      industry: "Small ecommerce skincare brand",
      sections: [
        { kind: "hero", props: { "headline" => "Skincare", "subheadline" => "A gentle routine", "cta" => "Shop" } },
        { kind: "product_grid", props: { "headline" => "Routine", "products" => [
          { "name" => "Barrier Repair Serum", "price" => "$34" },
          { "name" => "Calm Cream", "price" => "$28" },
          { "name" => "Mineral Cleanser", "price" => "$22" }
        ] } }
      ]
    )

    get "/s/coffee-visual-demo"
    expect(response.body).to include('data-illustration="coffee-hero"')
    expect(response.body).to include('data-illustration="coffee-feature-0"')
    expect(response.body).to include('data-illustration="coffee-feature-1"')
    expect(response.body).to include('data-illustration="coffee-feature-2"')

    get "/s/course-visual-demo"
    expect(response.body).to include('data-illustration="course-hero"')
    expect(response.body).to include('data-illustration="course-feature-0"')
    expect(response.body).to include('data-illustration="course-feature-1"')
    expect(response.body).to include('data-illustration="course-feature-2"')

    get "/s/skincare-visual-demo"
    expect(response.body).to include('data-illustration="skincare-hero"')
    expect(response.body).to include('data-illustration="skincare-product-serum"')
    expect(response.body).to include('data-illustration="skincare-product-cream"')
    expect(response.body).to include('data-illustration="skincare-product-cleanser"')
    expect(response.body).to include('aria-label="Barrier Repair Serum 产品图示"')
  end

  it "maps public forms by section uid when snapshot section ids are stale" do
    site = create(:site, slug: "uid-form-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    snapshot = Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    payload = snapshot.payload.deep_dup
    payload["pages"].first["sections"].first["id"] = section.id + 10_000
    snapshot.update!(payload:)

    get "/s/uid-form-demo"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("/s/uid-form-demo/forms/#{form.id}/submissions")
  end

  it "creates a contact, form submission, event, and aggregation job from public form submission" do
    site = create(:site, slug: "form-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", field_type: "email", required: true, position: 0)

    expect do
      post "/s/form-demo/forms/#{form.id}/submissions", params: {
        form_submission: { email: "lead@example.test", name: "Lead Person" }
      }
    end.to have_enqueued_job(AggregateEventJob)

    expect(response).to redirect_to("/s/form-demo?submitted=1")
    expect(site.contacts.find_by(email: "lead@example.test")).to be_present
    expect(form.form_submissions.count).to eq(1)
    expect(site.events.where(event_type: "form_submit").count).to eq(1)
  end

  it "rejects public form submissions without an email" do
    site = create(:site, slug: "invalid-form-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")

    expect do
      post "/s/invalid-form-demo/forms/#{form.id}/submissions", params: {
        form_submission: { name: "Lead Person" }
      }
    end.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.contacts.count).to eq(0)
    expect(form.form_submissions.count).to eq(0)
    expect(site.events.count).to eq(0)
  end

  it "records public interaction events" do
    site = create(:site, slug: "event-demo", status: "published")
    create(:page, site:)

    expect do
      post "/s/event-demo/events", params: { event_type: "cta_click", metadata: { target: "Start" } }
    end.to have_enqueued_job(AggregateEventJob)

    expect(response).to have_http_status(:accepted)
    expect(site.events.last).to have_attributes(event_type: "cta_click")
    expect(site.events.last.metadata).to eq("target" => "Start")
  end

  it "accepts public interaction events without a csrf token when forgery protection is enabled" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    site = create(:site, slug: "csrf-event-demo", status: "published")
    create(:page, site:)

    expect do
      post "/s/csrf-event-demo/events", params: { event_type: "cta_click", metadata: { target: "Start" } }
    end.to have_enqueued_job(AggregateEventJob)

    expect(response).to have_http_status(:accepted)
    expect(site.events.last).to have_attributes(event_type: "cta_click")
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  it "returns validation errors for invalid public interaction events" do
    site = create(:site, slug: "invalid-event-demo", status: "published")
    create(:page, site:)
    invalid_event = Event.new
    invalid_event.errors.add(:base, "event failed")
    allow_any_instance_of(Public::EventsController)
      .to receive(:record_public_event!)
      .and_raise(ActiveRecord::RecordInvalid.new(invalid_event))

    post "/s/invalid-event-demo/events", params: { event_type: "cta_click" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to include("事件未通过校验")
    expect(site.events.count).to eq(0)
  end

  it "accepts direct public form_start events" do
    site = create(:site, slug: "form-start-event-demo", status: "published")
    create(:page, site:)

    post "/s/form-start-event-demo/events", params: { event_type: "form_start" }

    expect(response).to have_http_status(:accepted)
    expect(site.events.last.event_type).to eq("form_start")
  end

  it "rejects direct public conversion events" do
    site = create(:site, slug: "direct-conversion-demo", status: "published")
    create(:page, site:)

    expect do
      post "/s/direct-conversion-demo/events", params: { event_type: "order_created" }
    end.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to include("该事件不能从公开页面直接上报")
    expect(site.events.count).to eq(0)

    post "/s/direct-conversion-demo/events", params: { event_type: "form_submit" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(site.events.count).to eq(0)
  end

  it "rejects direct public page_view events" do
    site = create(:site, slug: "direct-page-view-demo", status: "published")
    create(:page, site:)

    post "/s/direct-page-view-demo/events", params: { event_type: "page_view" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.events.count).to eq(0)
  end

  it "attributes public events to the experiment for the submitted section uid" do
    site = create(:site, slug: "section-event-demo", status: "published")
    page = create(:page, site:)
    contact_section = create(:section, page:, kind: "contact_form", position: 0)
    hero_section = create(:section, page:, kind: "hero", position: 1)
    contact_experiment = create(:experiment, site:, section: contact_section)
    hero_experiment = create(:experiment, site:, section: hero_section)
    create(:variant, experiment: contact_experiment, key: "contact", name: "Contact")
    create(:variant, experiment: hero_experiment, key: "hero", name: "Hero")

    post "/s/section-event-demo/events", params: { event_type: "cta_click", section_uid: hero_section.uid }

    expect(response).to have_http_status(:accepted)
    expect(site.events.last.experiment).to eq(hero_experiment)
    expect(site.events.last.variant_key).to eq("hero")
  end

  it "records public events without experiment attribution when section uid is missing" do
    site = create(:site, slug: "unattributed-event-demo", status: "published")
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant", name: "Variant")

    post "/s/unattributed-event-demo/events", params: { event_type: "cta_click" }

    expect(response).to have_http_status(:accepted)
    expect(site.events.last.experiment_id).to be_nil
    expect(site.events.last.variant_id).to be_nil
  end

  it "does not assign visitors to experiments whose sections are absent from the published snapshot" do
    site = create(:site, slug: "visible-sections-demo", status: "published")
    page = create(:page, site:)
    published_section = create(:section, page:, kind: "hero", position: 0)
    snapshot = Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    draft_only_section = create(:section, page:, kind: "faq", position: 1)
    visible_experiment = create(:experiment, site:, section: published_section)
    hidden_experiment = create(:experiment, site:, section: draft_only_section)
    create(:variant, experiment: visible_experiment, key: "visible", name: "Visible")
    create(:variant, experiment: hidden_experiment, key: "hidden", name: "Hidden")

    get "/s/visible-sections-demo"

    expect(response).to have_http_status(:ok)
    expect(visible_experiment.assignments.count).to eq(1)
    expect(hidden_experiment.assignments.count).to eq(0)
    expect(snapshot.payload.fetch("pages").first.fetch("sections").map { |section| section["uid"] }).not_to include(draft_only_section.uid)
  end

  it "rejects direct public events for hidden section experiments" do
    site = create(:site, slug: "hidden-event-demo", status: "published")
    page = create(:page, site:)
    create(:section, page:, kind: "hero", position: 0)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    draft_only_section = create(:section, page:, kind: "faq", position: 1)
    hidden_experiment = create(:experiment, site:, section: draft_only_section)
    create(:variant, experiment: hidden_experiment, key: "hidden", name: "Hidden")

    expect do
      post "/s/hidden-event-demo/events", params: { event_type: "cta_click", section_uid: draft_only_section.uid }
    end.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to have_http_status(:unprocessable_content)
    expect(hidden_experiment.assignments.count).to eq(0)
    expect(site.events.where(event_type: "cta_click").count).to eq(0)
  end

  it "rejects oversized public event metadata" do
    site = create(:site, slug: "large-event-demo", status: "published")
    create(:page, site:)

    expect do
      post "/s/large-event-demo/events", params: { event_type: "cta_click", metadata: { payload: "x" * 5.kilobytes } }
    end.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.events.count).to eq(0)
  end

  it "does not record page views for HEAD requests" do
    site = create(:site, slug: "head-demo", status: "published")
    page = create(:page, site:)
    create(:section, page:)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    expect do
      head "/s/head-demo"
    end.not_to have_enqueued_job(AggregateEventJob)

    expect(response).to have_http_status(:ok)
    expect(site.events.count).to eq(0)
  end
end
