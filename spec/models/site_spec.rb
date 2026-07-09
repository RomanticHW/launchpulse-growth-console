require "rails_helper"

RSpec.describe Site do
  it "destroys forms before their sections when destroying a site" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:, kind: "contact_form")
    site.forms.create!(section:, name: "Lead form")

    expect { site.destroy! }.not_to raise_error
    expect(Form.exists?(site_id: site.id)).to be(false)
  end

  it "enforces slug uniqueness globally, not only per account" do
    create(:site, account: create(:account), slug: "shared-shop")
    other = build(:site, account: create(:account), slug: "shared-shop")

    expect(other).not_to be_valid
    expect(other.errors[:slug]).to be_present
  end
end

