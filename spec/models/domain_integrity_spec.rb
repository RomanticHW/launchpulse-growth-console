require "rails_helper"

RSpec.describe "Domain integrity" do
  it "rejects cross-site experiment sections" do
    site = create(:site)
    other_page = create(:page)
    other_section = create(:section, page: other_page)

    experiment = build(:experiment, site:, section: other_section)

    expect(experiment).not_to be_valid
    expect(experiment.errors[:section]).to be_present
  end

  it "rejects cross-site form sections" do
    site = create(:site)
    other_page = create(:page)
    other_section = create(:section, page: other_page)

    form = site.forms.build(section: other_section, name: "Lead form")

    expect(form).not_to be_valid
    expect(form.errors[:section]).to be_present
  end

  it "rejects order items whose product belongs to another site" do
    order = create(:site).orders.create!(number: "ORD-1", email: "buyer@example.test", total: 10)
    product = create(:site).products.create!(name: "Other", price: 10)

    item = order.order_items.build(product:, quantity: 1, unit_price: 10)

    expect(item).not_to be_valid
    expect(item.errors[:product]).to be_present
  end

  it "rejects recommendations whose section belongs to another site" do
    site = create(:site)
    other_section = create(:section)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section: other_section, problem: "Weak CTA", severity: "high")

    recommendation = site.recommendations.build(
      ai_finding: finding,
      section: other_section,
      title: "Improve CTA",
      problem: "CTA is too generic",
      expected_impact: "+8%",
      confidence: 0.8
    )

    expect(recommendation).not_to be_valid
    expect(recommendation.errors[:section]).to be_present
  end

  it "rejects section patches whose section differs from the recommendation section" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    other_section = create(:section, page:, position: 1)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve CTA",
      problem: "CTA is too generic",
      expected_impact: "+8%",
      confidence: 0.8
    )

    patch = recommendation.build_section_patch(section: other_section, props_diff: { "cta" => "Start" })

    expect(patch).not_to be_valid
    expect(patch.errors[:section]).to be_present
  end

  it "rejects events with cross-site page, experiment, or variant references" do
    site = create(:site)
    other_site = create(:site)
    other_page = create(:page, site: other_site)
    experiment = create(:experiment, site: other_site)
    variant = create(:variant, experiment:)

    event = site.events.build(
      page: other_page,
      experiment:,
      variant:,
      event_type: "form_submit",
      visitor_id: "visitor-1",
      occurred_at: Time.current
    )

    expect(event).not_to be_valid
    expect(event.errors[:page]).to be_present
    expect(event.errors[:experiment]).to be_present
  end

  it "builds experiment factories with section and site aligned" do
    experiment = create(:experiment)

    expect(experiment.section.site).to eq(experiment.site)
    expect(experiment).to be_valid
  end

  it "rejects assignments whose variant belongs to another experiment" do
    experiment = create(:experiment)
    other_variant = create(:variant, experiment: create(:experiment))

    assignment = experiment.assignments.build(visitor_id: "visitor-1", variant: other_variant)

    expect(assignment).not_to be_valid
    expect(assignment.errors[:variant]).to be_present
  end

  it "rejects conversions whose event belongs to another site" do
    experiment = create(:experiment)
    variant = create(:variant, experiment:)
    assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)
    event = create(:site).events.create!(event_type: "form_submit", visitor_id: "visitor-1", occurred_at: Time.current)

    conversion = assignment.conversions.build(event:, conversion_type: "form_submit")

    expect(conversion).not_to be_valid
    expect(conversion.errors[:event]).to be_present
  end

  it "rejects conversions whose event visitor does not match the assignment" do
    experiment = create(:experiment)
    variant = create(:variant, experiment:)
    assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)
    event = experiment.site.events.create!(event_type: "form_submit", visitor_id: "visitor-2", occurred_at: Time.current)

    conversion = assignment.conversions.build(event:, conversion_type: "form_submit")

    expect(conversion).not_to be_valid
    expect(conversion.errors[:event]).to be_present
  end

  it "rejects conversions whose event variant differs from the assignment variant" do
    experiment = create(:experiment)
    control = create(:variant, experiment:, key: "control")
    variant = create(:variant, experiment:, key: "variant")
    assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant: control)
    event = experiment.site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-1",
      experiment:,
      variant:,
      variant_key: variant.key,
      occurred_at: Time.current
    )

    conversion = assignment.conversions.build(event:, conversion_type: "form_submit")

    expect(conversion).not_to be_valid
    expect(conversion.errors[:event]).to be_present
  end

  it "rejects conversions whose event experiment differs from the assignment experiment" do
    experiment = create(:experiment)
    other_experiment = create(:experiment, site: experiment.site)
    variant = create(:variant, experiment:)
    other_variant = create(:variant, experiment: other_experiment)
    assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)
    event = experiment.site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-1",
      experiment: other_experiment,
      variant: other_variant,
      variant_key: other_variant.key,
      occurred_at: Time.current
    )

    conversion = assignment.conversions.build(event:, conversion_type: "form_submit")

    expect(conversion).not_to be_valid
    expect(conversion.errors[:event]).to be_present
  end

  it "rejects conversions without an explicit conversion type" do
    experiment = create(:experiment)
    variant = create(:variant, experiment:)
    assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)

    conversion = assignment.conversions.build(conversion_type: nil)

    expect(conversion).not_to be_valid
    expect(conversion.errors[:conversion_type]).to be_present
  end

  it "only allows real conversion types" do
    experiment = create(:experiment)
    variant = create(:variant, experiment:)
    assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)

    %w[page_view cta_click form_start product_view checkout_click].each do |event_type|
      conversion = assignment.conversions.build(conversion_type: event_type)

      expect(conversion).not_to be_valid
      expect(conversion.errors[:conversion_type]).to be_present
    end

    %w[form_submit order_created any_conversion].each do |event_type|
      conversion = assignment.conversions.build(conversion_type: event_type)

      expect(conversion).to be_valid
    end
  end

  it "does not default conversion type to an invalid value" do
    column = Conversion.columns_hash.fetch("conversion_type")

    expect(column.default).to be_nil
  end

  it "rejects checkout clicks as experiment primary goals" do
    experiment = build(:experiment, primary_goal: "checkout_click")

    expect(experiment).not_to be_valid
    expect(experiment.errors[:primary_goal]).to be_present
  end

  it "destroys experiments after a winner variant has been applied" do
    experiment = create(:experiment, status: "completed")
    winner = create(:variant, experiment:, key: "winner")
    experiment.update!(winner_variant: winner, winner_applied_at: Time.current)

    expect { experiment.destroy! }.to change(Experiment, :count).by(-1)
  end

  it "destroys a site that has a completed experiment winner" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, status: "completed")
    winner = create(:variant, experiment:, key: "winner")
    experiment.update!(winner_variant: winner, winner_applied_at: Time.current)

    expect { site.destroy! }.to change(Site, :count).by(-1)
  end

  it "destroys an account after a winner variant has been applied" do
    account = create(:account)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, status: "completed")
    winner = create(:variant, experiment:, key: "winner")
    experiment.update!(winner_variant: winner, winner_applied_at: Time.current)

    expect { account.destroy! }.to change(Account, :count).by(-1)
  end

  it "destroys an account after checkout, attributed conversion, and applied winner" do
    account = create(:account)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:, kind: "product_grid")
    product = site.products.create!(name: "Calm Cream", key: "calm-cream", price: 28)
    order = site.orders.create!(number: "ORD-1", email: "buyer@example.test", total: 28)
    order.order_items.create!(product:, quantity: 1, unit_price: 28)
    experiment = create(:experiment, site:, section:, status: "completed", primary_goal: "order_created")
    variant = create(:variant, experiment:, key: "winner")
    assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)
    event = site.events.create!(
      page:,
      event_type: "order_created",
      visitor_id: "visitor-1",
      experiment:,
      variant:,
      variant_key: variant.key,
      occurred_at: Time.current
    )
    assignment.conversions.create!(event:, conversion_type: "order_created")
    experiment.update!(winner_variant: variant, winner_applied_at: Time.current)

    expect { account.destroy! }.not_to raise_error
    expect(Account.exists?(account.id)).to be(false)
  end

  it "rejects event variant key mismatches" do
    experiment = create(:experiment)
    variant = create(:variant, experiment:, key: "variant")

    event = experiment.site.events.build(
      event_type: "cta_click",
      visitor_id: "visitor-1",
      experiment:,
      variant:,
      variant_key: "control",
      occurred_at: Time.current
    )

    expect(event).not_to be_valid
    expect(event.errors[:variant_key]).to be_present
  end

  it "allows idempotent events with a payload fingerprint" do
    site = create(:site)
    event = site.events.build(
      event_type: "page_view",
      visitor_id: "visitor-idempotent",
      idempotency_key: "event-idempotent",
      payload_fingerprint: "fingerprint",
      occurred_at: Time.current
    )

    expect(event).to be_valid
  end

  it "rejects idempotent events without a payload fingerprint" do
    site = create(:site)
    event = site.events.build(
      event_type: "page_view",
      visitor_id: "visitor-missing-fingerprint",
      idempotency_key: "event-missing-fingerprint",
      payload_fingerprint: nil,
      occurred_at: Time.current
    )

    expect(event).not_to be_valid
    expect(event.errors[:payload_fingerprint]).to be_present
  end

  it "allows non-idempotent events without a payload fingerprint" do
    site = create(:site)
    event = site.events.build(
      event_type: "page_view",
      visitor_id: "visitor-no-idempotency",
      payload_fingerprint: nil,
      occurred_at: Time.current
    )

    expect(event).to be_valid
  end

  it "rejects events whose metadata is not an object" do
    site = create(:site)
    event = site.events.build(
      event_type: "page_view",
      visitor_id: "visitor-array-metadata",
      occurred_at: Time.current,
      metadata: [ "campaign", "spring" ]
    )

    expect(event).not_to be_valid
    expect(event.errors[:metadata]).to be_present
  end

  it "rejects non-conversion primary goals" do
    experiment = build(:experiment, primary_goal: "page_view")

    expect(experiment).not_to be_valid
    expect(experiment.errors[:primary_goal]).to be_present
  end

  it "counts experiment conversions by primary goal and distinct assignments" do
    experiment = create(:experiment, primary_goal: "form_submit")
    variant = create(:variant, experiment:, key: "variant")
    assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)
    event = experiment.site.events.create!(event_type: "form_submit", visitor_id: "visitor-1", occurred_at: Time.current)
    assignment.conversions.create!(event:, conversion_type: "form_submit")
    assignment.conversions.create!(conversion_type: "order_created")

    expect(experiment.conversions_count).to eq(1)
    expect(variant.conversions_count).to eq(1)
    expect(experiment.conversion_rate).to eq(100.to_d)
    expect(variant.conversion_rate).to eq(100.to_d)
  end

  it "counts any-conversion experiments once per assignment" do
    experiment = create(:experiment, primary_goal: "any_conversion")
    variant = create(:variant, experiment:, key: "variant")
    assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)
    assignment.conversions.create!(conversion_type: "form_submit")
    assignment.conversions.create!(conversion_type: "order_created")

    expect(experiment.conversions_count).to eq(1)
    expect(variant.conversions_count).to eq(1)
    expect(experiment.conversion_rate).to eq(100.to_d)
  end

  it "validates product keys" do
    site = create(:site)
    site.products.create!(name: "Calm Cream", key: "calm-cream", price: 28)
    duplicate = site.products.build(name: "Other", key: "calm-cream", price: 22)
    invalid = site.products.build(name: "Invalid", key: "Calm Cream", price: 22)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:key]).to be_present
    expect(invalid).not_to be_valid
    expect(invalid.errors[:key]).to be_present
  end

  it "validates stable form field keys and field types" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    form = site.forms.create!(section:, name: "Lead form")
    form.form_fields.create!(label: "Email", key: "email", field_type: "email")
    duplicate = form.form_fields.build(label: "Other email", key: "email", field_type: "email")
    invalid = form.form_fields.build(label: "Bad", key: "Bad Key", field_type: "unknown")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:key]).to be_present
    expect(invalid).not_to be_valid
    expect(invalid.errors[:key]).to be_present
    expect(invalid.errors[:field_type]).to be_present
  end
end

RSpec.describe "Experiment conversion scopes" do
  it "open_for_conversion includes paused experiments without winner" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    paused = create(:experiment, site:, section:, status: "paused", winner_applied_at: nil)
    applied = create(:experiment, site:, section: create(:section, page:, position: 1), status: "completed", winner_applied_at: Time.current)

    expect(site.experiments.open_for_conversion).to include(paused)
    expect(site.experiments.open_for_conversion).not_to include(applied)
  end
end
