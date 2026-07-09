FactoryBot.define do
  factory :membership do
    account
    user
    role { "owner" }
  end
end
