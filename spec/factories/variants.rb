FactoryBot.define do
  factory :variant do
    experiment
    sequence(:key) { |n| "variant-#{n}" }
    name { key.humanize }
    role { "variant" }
    props { {} }
  end
end
