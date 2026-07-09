FactoryBot.define do
  factory :site do
    account
    name { "Test Site" }
    sequence(:slug) { |n| "test-site-#{n}" }
    industry { "Landing page" }
    growth_score { 72 }
    status { "published" }
  end
end
