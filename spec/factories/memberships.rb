FactoryBot.define do
  factory :membership do
    account
    user
    role { Membership::OWNER }
  end
end
