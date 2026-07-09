require "rails_helper"

RSpec.describe "Event API" do
  def signed_token_for(site)
    key, raw_token = ApiKey.issue!(site:)
    key.signed_token(raw_token)
  end

  it "accepts a signed site token and enqueues aggregation" do
    site = create(:site)
    page = create(:page, site:)
    signed_token = signed_token_for(site)

    expect do
      post "/api/v1/events", params: {
        site_token: signed_token,
        event_type: "page_view",
        visitor_id: "visitor-1",
        session_id: "session-1",
        source: "search",
        device: "mobile",
        page_path: page.path,
        metadata: { campaign: "spring" }
      }
    end.to have_enqueued_job(AggregateEventJob)

    expect(response).to have_http_status(:accepted)
    expect(site.events.last).to have_attributes(event_type: "page_view", visitor_id: "visitor-1", source: "search", device: "mobile")
  end

  it "rejects invalid tokens" do
    post "/api/v1/events", params: {
      site_token: "bad-token",
      event_type: "page_view",
      visitor_id: "visitor-1"
    }

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a missing site token" do
    post "/api/v1/events", params: {
      event_type: "page_view",
      visitor_id: "visitor-1"
    }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body).fetch("error")).to match(/site token/i)
  end

  it "rejects missing event type" do
    site = create(:site)

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      visitor_id: "visitor-1"
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to match(/event_type/i)
  end

  it "rejects missing visitor id" do
    site = create(:site)

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      event_type: "page_view"
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to match(/visitor_id/i)
  end

  it "rejects invalid event type" do
    site = create(:site)

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      event_type: "made_up",
      visitor_id: "visitor-1"
    }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "preserves nested metadata for the sanitizer" do
    site = create(:site)
    token = signed_token_for(site)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-nested",
      metadata: {
        campaign: {
          source: "newsletter",
          tags: [ "spring", "vip" ]
        }
      }
    }, as: :json

    expect(response).to have_http_status(:accepted)
    expect(site.events.last.metadata).to include(
      "campaign" => {
        "source" => "newsletter",
        "tags" => [ "spring", "vip" ]
      }
    )
  end

  it "rejects top-level array metadata" do
    site = create(:site)
    token = signed_token_for(site)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-array-metadata",
      metadata: [ "campaign", "spring" ]
    }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to match(/metadata must be an object/i)
    expect(site.events.count).to eq(0)
  end

  it "ignores unknown top-level params while preserving nested metadata" do
    site = create(:site)
    token = signed_token_for(site)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-extra-param",
      unexpected_top_level: "should-not-persist",
      metadata: { campaign: { tags: [ "spring" ] } }
    }, as: :json

    expect(response).to have_http_status(:accepted)
    expect(site.events.last.metadata).to eq("campaign" => { "tags" => [ "spring" ] })
  end

  it "lets the metadata sanitizer reject too-deep API metadata" do
    site = create(:site)
    token = signed_token_for(site)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-too-deep",
      metadata: { a: { b: { c: { d: { e: { f: "too deep" } } } } } }
    }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to match(/metadata is too deep/i)
    expect(site.events.count).to eq(0)
  end

  it "returns the existing event for a duplicate idempotency key" do
    site = create(:site)
    token = signed_token_for(site)

    2.times do
      post "/api/v1/events", params: {
        site_token: token,
        event_type: "page_view",
        visitor_id: "visitor-1",
        idempotency_key: "event-123"
      }
    end

    expect(response).to have_http_status(:accepted)
    expect(site.events.where(idempotency_key: "event-123").count).to eq(1)
  end

  it "rejects duplicate idempotency keys when the payload changes" do
    site = create(:site)
    token = signed_token_for(site)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-1",
      idempotency_key: "event-mismatch"
    }
    post "/api/v1/events", params: {
      site_token: token,
      event_type: "order_created",
      visitor_id: "visitor-1",
      idempotency_key: "event-mismatch"
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to match(/idempotency key payload mismatch/i)
    expect(site.events.where(idempotency_key: "event-mismatch").count).to eq(1)
  end

  it "rejects existing idempotent events that are missing a payload fingerprint" do
    site = create(:site)
    token = signed_token_for(site)
    event = site.events.create!(
      event_type: "page_view",
      visitor_id: "visitor-blank-fingerprint",
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )
    event.update_columns(idempotency_key: "event-blank-fingerprint", payload_fingerprint: nil)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-blank-fingerprint",
      idempotency_key: "event-blank-fingerprint"
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to match(/payload fingerprint missing/i)
    expect(site.events.where(idempotency_key: "event-blank-fingerprint").count).to eq(1)
  end

  it "rejects duplicate idempotency payload changes before section attribution creates assignments" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant", name: "Variant")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    token = signed_token_for(site)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-section-mismatch",
      idempotency_key: "event-section-mismatch"
    }
    post "/api/v1/events", params: {
      site_token: token,
      event_type: "cta_click",
      visitor_id: "visitor-section-mismatch",
      section_uid: section.uid,
      idempotency_key: "event-section-mismatch"
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to match(/idempotency key payload mismatch/i)
    expect(experiment.assignments.count).to eq(0)
  end

  it "rejects duplicate idempotency payload changes before explicit attribution creates assignments" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    variant = create(:variant, experiment:, key: "recommended", name: "Recommended")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    token = signed_token_for(site)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-explicit-mismatch",
      idempotency_key: "event-explicit-mismatch"
    }
    post "/api/v1/events", params: {
      site_token: token,
      event_type: "cta_click",
      visitor_id: "visitor-explicit-mismatch",
      experiment_id: experiment.id,
      variant_key: variant.key,
      idempotency_key: "event-explicit-mismatch"
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to match(/idempotency key payload mismatch/i)
    expect(experiment.assignments.count).to eq(0)
  end

  it "keeps duplicate idempotent section events to one assignment and one aggregation job" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant", name: "Variant")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    token = signed_token_for(site)

    expect do
      2.times do
        post "/api/v1/events", params: {
          site_token: token,
          event_type: "cta_click",
          visitor_id: "visitor-section-duplicate",
          section_uid: section.uid,
          idempotency_key: "event-section-duplicate"
        }
      end
    end.to have_enqueued_job(AggregateEventJob).once

    expect(response).to have_http_status(:accepted)
    expect(experiment.assignments.count).to eq(1)
    expect(site.events.where(idempotency_key: "event-section-duplicate").count).to eq(1)
  end

  it "rejects duplicate idempotency keys when only metadata type changes" do
    site = create(:site)
    token = signed_token_for(site)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-1",
      idempotency_key: "event-type-aware",
      metadata: { count: 1 }
    }, as: :json
    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-1",
      idempotency_key: "event-type-aware",
      metadata: { count: "1" }
    }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to match(/idempotency key payload mismatch/i)
  end

  it "checks fingerprint mismatch after an idempotency uniqueness race" do
    site = create(:site)
    token = signed_token_for(site)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-1",
      idempotency_key: "event-race"
    }

    allow_any_instance_of(ActiveRecord::Associations::CollectionProxy)
      .to receive(:create!)
      .and_raise(ActiveRecord::RecordNotUnique)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "order_created",
      visitor_id: "visitor-1",
      idempotency_key: "event-race"
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to match(/idempotency key payload mismatch/i)
    expect(site.events.where(idempotency_key: "event-race").count).to eq(1)
  end

  it "rolls back attribution side effects when a late idempotency race finds a mismatch" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant", name: "Variant")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    token = signed_token_for(site)

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "page_view",
      visitor_id: "visitor-late-race",
      idempotency_key: "event-late-race"
    }

    calls = 0
    allow_any_instance_of(Events::IngestionService)
      .to receive(:existing_idempotent_event)
      .and_wrap_original do |original, site_arg, key_arg, fingerprint_arg|
        calls += 1
        calls == 1 ? nil : original.call(site_arg, key_arg, fingerprint_arg)
      end

    post "/api/v1/events", params: {
      site_token: token,
      event_type: "cta_click",
      visitor_id: "visitor-late-race",
      section_uid: section.uid,
      idempotency_key: "event-late-race"
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to match(/idempotency key payload mismatch/i)
    expect(experiment.assignments.count).to eq(0)
  end

  it "does not enqueue aggregation twice for duplicate idempotency keys" do
    site = create(:site)
    token = signed_token_for(site)

    expect do
      2.times do
        post "/api/v1/events", params: {
          site_token: token,
          event_type: "page_view",
          visitor_id: "visitor-1",
          idempotency_key: "event-456"
        }
      end
    end.to have_enqueued_job(AggregateEventJob).once
  end

  it "attributes events by section uid and creates an assignment" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant", name: "Variant")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      event_type: "cta_click",
      visitor_id: "visitor-section",
      section_uid: section.uid
    }

    expect(response).to have_http_status(:accepted)
    expect(site.events.last.experiment).to eq(experiment)
    expect(experiment.assignments.find_by(visitor_id: "visitor-section")).to be_present
  end

  it "rolls back section assignment when non-idempotent event creation fails" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant", name: "Variant")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    invalid_event = Event.new
    invalid_event.errors.add(:base, "event failed")
    allow_any_instance_of(Events::IngestionService)
      .to receive(:find_or_create_event!)
      .and_raise(ActiveRecord::RecordInvalid.new(invalid_event))

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      event_type: "cta_click",
      visitor_id: "visitor-rollback",
      section_uid: section.uid
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(experiment.assignments.count).to eq(0)
    expect(site.events.count).to eq(0)
  end

  it "rejects section attribution when the section is not published" do
    site = create(:site)
    page = create(:page, site:)
    create(:section, page:)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    hidden_section = create(:section, page:, position: 1)
    experiment = create(:experiment, site:, section: hidden_section)
    create(:variant, experiment:, key: "variant", name: "Variant")

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      event_type: "cta_click",
      visitor_id: "visitor-hidden",
      section_uid: hidden_section.uid
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(experiment.assignments.count).to eq(0)
    expect(site.events.count).to eq(0)
  end

  it "attributes events by experiment id and variant key" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    variant = create(:variant, experiment:, key: "recommended", name: "Recommended")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      event_type: "cta_click",
      visitor_id: "visitor-explicit",
      experiment_id: experiment.id,
      variant_key: variant.key
    }

    expect(response).to have_http_status(:accepted)
    expect(site.events.last.experiment).to eq(experiment)
    expect(site.events.last.variant).to eq(variant)
    expect(experiment.assignments.find_by(visitor_id: "visitor-explicit")&.variant).to eq(variant)
  end

  it "rejects explicit attribution when the experiment section is hidden" do
    site = create(:site)
    page = create(:page, site:)
    create(:section, page:)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    hidden_section = create(:section, page:, position: 1)
    experiment = create(:experiment, site:, section: hidden_section)
    variant = create(:variant, experiment:, key: "recommended", name: "Recommended")

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      event_type: "cta_click",
      visitor_id: "visitor-hidden-explicit",
      experiment_id: experiment.id,
      variant_key: variant.key
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(experiment.assignments.count).to eq(0)
    expect(site.events.count).to eq(0)
  end

  it "counts explicit attributed conversion events" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    variant = create(:variant, experiment:, key: "recommended", name: "Recommended")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      event_type: "form_submit",
      visitor_id: "visitor-explicit-conversion",
      experiment_id: experiment.id,
      variant_key: variant.key
    }
    event = site.events.last

    Analytics::AggregationService.new(event).call

    assignment = experiment.assignments.find_by!(visitor_id: "visitor-explicit-conversion")
    expect(assignment.variant).to eq(variant)
    expect(assignment.conversions.where(conversion_type: "form_submit").count).to eq(1)
  end

  it "rejects explicit attribution that conflicts with an existing assignment" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    control = create(:variant, experiment:, key: "control", name: "Control", role: "control")
    variant = create(:variant, experiment:, key: "recommended", name: "Recommended")
    experiment.assignments.create!(visitor_id: "visitor-conflict", variant: control)

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      event_type: "cta_click",
      visitor_id: "visitor-conflict",
      experiment_id: experiment.id,
      variant_key: variant.key
    }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects experiment attribution from another site" do
    site = create(:site)
    other_site = create(:site)
    page = create(:page, site: other_site)
    section = create(:section, page:)
    other_experiment = create(:experiment, site: other_site, section:)
    create(:variant, experiment: other_experiment, key: "variant", name: "Variant")

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      event_type: "cta_click",
      visitor_id: "visitor-wrong-site",
      experiment_id: other_experiment.id,
      variant_key: "variant"
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(site.events.count).to eq(0)
  end

  it "still accepts authenticated order_created events" do
    site = create(:site)

    post "/api/v1/events", params: {
      site_token: signed_token_for(site),
      event_type: "order_created",
      visitor_id: "visitor-api-order",
      idempotency_key: "api-order-1"
    }

    expect(response).to have_http_status(:accepted)
    expect(site.events.last.event_type).to eq("order_created")
  end
end
