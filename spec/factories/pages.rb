FactoryBot.define do
  factory :page do
    site
    title { "Home" }
    path { "/" }
    position { 0 }
  end
end
