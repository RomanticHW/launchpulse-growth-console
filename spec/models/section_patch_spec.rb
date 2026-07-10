require "rails_helper"

RSpec.describe SectionPatch do
  def build_patch(status: "pending")
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:, props: { "headline" => "Original" })
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak headline", severity: "medium")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve headline",
      problem: "Weak headline",
      expected_impact: "More clicks",
      confidence: 0.8,
      suggested_patch: { "headline" => "Better" }
    )
    patch = described_class.create!(
      recommendation:,
      section:,
      props_diff: { "headline" => "Better" },
      before_props: { "headline" => "Original" },
      after_props: { "headline" => "Better" },
      status:
    )
    [ patch, section ]
  end

  it "does not revert a patch that has not been applied" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:, props: { "headline" => "Original" })
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak headline", severity: "medium")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve headline",
      problem: "Weak headline",
      expected_impact: "More clicks",
      confidence: 0.8,
      suggested_patch: { "headline" => "Better" }
    )
    patch = described_class.create!(recommendation:, section:, props_diff: { "headline" => "Better" })

    expect { patch.revert! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(section.reload.props).to eq("headline" => "Original")
  end

  it "applies without mutating immutable before and after props" do
    patch, section = build_patch
    section.update!(props: { "headline" => "Changed draft" })

    patch.apply!

    expect(section.reload.props).to eq("headline" => "Better")
    expect(patch.reload.before_props).to eq("headline" => "Original")
    expect(patch.after_props).to eq("headline" => "Better")
  end

  it "locks the site before the patch while applying" do
    patch, section = build_patch
    site = patch.section.site
    site_lock_held = false

    expect(site).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      original.call(*args) do
        site_lock_held = true
        block.call
      ensure
        site_lock_held = false
      end
    end
    expect(patch).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      expect(site_lock_held).to be(true)
      original.call(*args, &block)
    end

    patch.apply!

    expect(section.reload.props).to eq("headline" => "Better")
  end

  it "locks the site before the patch while reverting" do
    patch, section = build_patch
    patch.apply!
    site = patch.section.site
    site_lock_held = false

    expect(site).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      original.call(*args) do
        site_lock_held = true
        block.call
      ensure
        site_lock_held = false
      end
    end
    expect(patch).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      expect(site_lock_held).to be(true)
      original.call(*args, &block)
    end

    patch.revert!

    expect(section.reload.props).to eq("headline" => "Original")
  end

  it "is idempotent when already applied" do
    patch, section = build_patch
    patch.apply!

    expect { patch.reload.apply! }.not_to change { section.reload.props }
  end

  it "rejects testing patches for apply and dismiss" do
    patch, = build_patch(status: "testing")

    expect { patch.apply! }.to raise_error(ActiveRecord::RecordInvalid)
    expect { patch.dismiss! }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "rejects dismissing an applied patch before reverting" do
    patch, = build_patch
    patch.apply!

    expect { patch.reload.dismiss! }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "rejects tested and superseded patches for apply and dismiss" do
    tested_patch, = build_patch(status: "tested")
    superseded_patch, = build_patch(status: "superseded")

    expect { tested_patch.apply! }.to raise_error(ActiveRecord::RecordInvalid)
    expect { tested_patch.dismiss! }.to raise_error(ActiveRecord::RecordInvalid)
    expect { superseded_patch.apply! }.to raise_error(ActiveRecord::RecordInvalid)
    expect { superseded_patch.dismiss! }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "allows reverted patches to apply again" do
    patch, section = build_patch
    patch.apply!
    patch.revert!

    patch.reload.apply!

    expect(section.reload.props).to eq("headline" => "Better")
    expect(patch.reload.status).to eq("applied")
  end
end
