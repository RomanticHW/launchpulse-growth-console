require "rails_helper"

RSpec.describe Sites::SnapshotService do
  it "sets the site status to published and stores a checksum" do
    site = create(:site, status: "draft")
    page = create(:page, site:)
    create(:section, page:)
    service = described_class.new(site)

    snapshot = service.publish!(user: nil, note: "Version 1")

    expect(site.reload.status).to eq("published")
    expect(snapshot.checksum).to eq(Digest::SHA256.hexdigest(service.send(:canonical_json, snapshot.payload)))
    expect(snapshot.published_at).to be_present
  end

  it "verifies a reloaded snapshot checksum" do
    site = create(:site, status: "draft")
    page = create(:page, site:)
    create(:section, page:, props: { "headline" => "Published", "items" => [ { "label" => "One", "value" => 1 } ] })
    snapshot = described_class.new(site).publish!(user: nil, note: "Version 1")

    reloaded_snapshot = PublishedSnapshot.find(snapshot.id)

    expect { described_class.new(site).rollback!(reloaded_snapshot, user: nil) }.not_to raise_error
  end

  it "uses the same checksum for the same payload with different hash key order" do
    service = described_class.new(create(:site))
    payload = {
      "b" => { "y" => 2, "x" => [ { "d" => 4, "c" => 3 } ] },
      "a" => 1
    }
    reordered_payload = {
      a: 1,
      b: { x: [ { c: 3, d: 4 } ], y: 2 }
    }

    expect(service.send(:checksum_for, payload)).to eq(service.send(:checksum_for, reordered_payload))
    expect(service.send(:checksum_for, payload)).not_to eq(Digest::SHA256.hexdigest(payload.to_json))
  end

  it "changes the checksum when payload content changes" do
    service = described_class.new(create(:site))
    payload = { "site" => { "name" => "Before" }, "pages" => [] }
    changed_payload = { "site" => { "name" => "After" }, "pages" => [] }

    expect(service.send(:checksum_for, payload)).not_to eq(service.send(:checksum_for, changed_payload))
  end

  it "removes draft sections that are not present in the rollback snapshot" do
    site = create(:site, status: "published")
    page = create(:page, site:)
    published_section = create(:section, page:, kind: "hero", position: 0, props: { "headline" => "Published" })
    snapshot = described_class.new(site).publish!(user: nil, note: "Version 1")

    create(:section, page:, kind: "faq", name: "Draft FAQ", position: 1, props: { "items" => [] })

    described_class.new(site).rollback!(snapshot, user: nil)

    expect(page.sections.reload.pluck(:uid)).to contain_exactly(published_section.uid)
  end

  it "removes draft pages that are not present in the rollback snapshot" do
    site = create(:site, status: "published")
    home_page = create(:page, site:, path: "/", position: 0)
    create(:section, page: home_page, kind: "hero", position: 0, props: { "headline" => "Published" })
    snapshot = described_class.new(site).publish!(user: nil, note: "Version 1")

    draft_page = create(:page, site:, path: "/about", position: 1)
    create(:section, page: draft_page, kind: "faq", name: "Draft FAQ", position: 0, props: { "items" => [] })

    described_class.new(site).rollback!(snapshot, user: nil)

    expect(site.pages.reload.pluck(:path)).to contain_exactly("/")
    expect(Page.exists?(draft_page.id)).to be(false)
  end

  it "verifies snapshot checksum before rollback" do
    site = create(:site, status: "published")
    page = create(:page, site:)
    create(:section, page:, kind: "hero", position: 0, props: { "headline" => "Published" })
    snapshot = described_class.new(site).publish!(user: nil, note: "Version 1")
    snapshot.update_column(:checksum, "tampered")

    expect { described_class.new(site).rollback!(snapshot, user: nil) }.to raise_error(Sites::SnapshotService::ChecksumMismatch)
  end

  it "rejects rollback when a reloaded snapshot payload was changed" do
    site = create(:site, status: "published")
    page = create(:page, site:)
    create(:section, page:, kind: "hero", position: 0, props: { "headline" => "Published" })
    snapshot = described_class.new(site).publish!(user: nil, note: "Version 1")
    payload = snapshot.payload.deep_dup
    payload["pages"].first["sections"].first["props"]["headline"] = "Changed"
    snapshot.update_column(:payload, payload)

    expect { described_class.new(site).rollback!(snapshot.reload, user: nil) }.to raise_error(Sites::SnapshotService::ChecksumMismatch)
  end

  it "preserves section id and form association when rolling back by uid" do
    site = create(:site, status: "published")
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form", position: 0, props: { "headline" => "Published" })
    form = site.forms.create!(section:, name: "Lead form")
    snapshot = described_class.new(site).publish!(user: nil, note: "Version 1")
    section.update!(props: { "headline" => "Draft" })

    described_class.new(site).rollback!(snapshot, user: nil)

    expect(section.reload.id).to eq(form.reload.section_id)
    expect(section.props).to eq("headline" => "Published")
  end
end
