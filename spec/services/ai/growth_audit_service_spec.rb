require "rails_helper"

RSpec.describe Ai::GrowthAuditService do
  it "does not create contact form patches for sites without contact form sections" do
    site = create(:site)
    page = create(:page, site:)
    create(:section, page:, kind: "hero")
    create(:section, page:, kind: "product_grid", position: 1, props: { "headline" => "Products", "products" => [] })

    described_class.new(site).call

    patches = SectionPatch.joins(:recommendation).where(recommendations: { site_id: site.id })
    expect(patches.joins(:section).where(sections: { kind: "contact_form" })).to be_empty
    expect(patches.where("props_diff ? :key", key: "submit_label")).to be_empty
  end

  it "creates schema-compatible patches for each target section kind" do
    site = create(:site)
    page = create(:page, site:)
    Section::KINDS.each_with_index do |kind, index|
      create(:section, page:, kind:, name: kind.humanize, position: index, props: props_for(kind))
    end

    described_class.new(site).call

    SectionPatch.joins(:recommendation).where(recommendations: { site_id: site.id }).includes(:section).find_each do |patch|
      expect(patch.props_diff.keys).to all(be_in(allowed_keys_for(patch.section.kind)))
      expect(patch.after_props).to include(*patch.props_diff.keys)
    end
  end

  it "does not duplicate deterministic recommendations in terminal recommendation states" do
    site = create(:site)
    page = create(:page, site:)
    create(:section, page:, kind: "hero")

    %w[tested superseded dismissed].each do |status|
      site.recommendations.destroy_all
      described_class.new(site).call
      site.recommendations.first.update!(status:)

      expect { described_class.new(site).call }.not_to change { site.recommendations.count }
    end
  end

  def props_for(kind)
    case kind
    when "feature_grid"
      { "headline" => "Features", "items" => [] }
    when "contact_form"
      { "headline" => "Contact", "helper" => "Help", "submit_label" => "Submit" }
    when "product_grid"
      { "headline" => "Products", "products" => [] }
    when "pricing"
      { "headline" => "Pricing", "plans" => [] }
    when "faq"
      { "headline" => "FAQ", "items" => [] }
    when "testimonial"
      { "quote" => "Useful", "author" => "Customer" }
    else
      { "eyebrow" => "Demo", "headline" => "Headline", "subheadline" => "Body", "cta" => "Start" }
    end
  end

  def allowed_keys_for(kind)
    {
      "hero" => %w[eyebrow headline subheadline cta],
      "feature_grid" => %w[headline items],
      "contact_form" => %w[headline helper submit_label],
      "pricing" => %w[headline plans],
      "product_grid" => %w[headline products],
      "faq" => %w[headline items],
      "testimonial" => %w[quote author]
    }.fetch(kind)
  end
end
