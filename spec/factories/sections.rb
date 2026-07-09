FactoryBot.define do
  factory :section do
    page
    kind { "hero" }
    name { "Hero" }
    position { 0 }
    props { { "headline" => "Grow faster", "subheadline" => "A clearer value proposition.", "cta" => "Start" } }
  end
end
