FactoryBot.define do
  factory :experiment do
    site
    section do
      page = site.pages.first || association(:page, site:)
      association(:section, page:)
    end
    name { "Hero CTA test" }
    status { "active" }
    started_at { Time.current }
  end
end
