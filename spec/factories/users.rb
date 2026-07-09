FactoryBot.define do
  factory :user do
    name { "Demo User" }
    sequence(:email) { |n| "user#{n}@example.test" }
    password { "password" }
  end
end
