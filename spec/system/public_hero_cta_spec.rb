require "rails_helper"

RSpec.describe "Public hero CTA", type: :system, js: true do
  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]
  end

  it "scrolls to the contact section without revisiting the public page" do
    site = create(:site, slug: "hero-cta-browser-demo", status: "published")
    page_record = create(:page, site:)
    create(:section, page: page_record, kind: "hero", props: { "headline" => "Ship with confidence", "subheadline" => "See the next step.", "cta" => "Contact us" })
    contact_section = create(:section, page: page_record, kind: "contact_form", position: 1)
    form = site.forms.create!(section: contact_section, name: "Lead form")
    form.form_fields.create!(label: "Email", field_type: "email", required: true, position: 0)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    visit public_site_path(site.slug)

    expect(Event.where(site:, event_type: "page_view").count).to eq(1)
    page.execute_script(<<~JAVASCRIPT)
      window.__turboVisitCount = 0
      window.__turboLoadCount = 0
      document.addEventListener("turbo:before-visit", () => {
        window.__turboVisitCount += 1
      })
      document.addEventListener("turbo:load", () => {
        window.__turboLoadCount += 1
        document.documentElement.dataset.turboLoadCount = String(window.__turboLoadCount)
      })

      const originalFetch = window.fetch.bind(window)
      window.fetch = (...argumentsList) => {
        const request = originalFetch(...argumentsList)
        request.finally(() => {
          document.documentElement.dataset.ctaTrackingSettled = "true"
        })
        return request
      }
    JAVASCRIPT

    click_link "Contact us"

    expect(page).to have_css('html[data-cta-tracking-settled="true"]')
    if page.evaluate_script("window.__turboVisitCount").positive?
      expect(page).to have_css('html[data-turbo-load-count="1"]')
    end
    expect(Event.where(site:, event_type: "cta_click").count).to eq(1)
    expect(Event.where(site:, event_type: "page_view").count).to eq(1)
    expect(page).to have_css("#contact")
    expect(page.evaluate_script("window.location.hash")).to eq("#contact")
    expect(URI.parse(page.current_url).path).to eq(public_site_path(site.slug))
    expect(page.evaluate_script("window.__turboVisitCount")).to eq(0)
  end
end
