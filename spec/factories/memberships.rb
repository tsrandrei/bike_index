FactoryBot.define do
  factory :membership do
    role { "member" }
    organization { FactoryBot.create(:organization) }
    factory :existing_membership do
      user { FactoryBot.create(:user) }
    end

    factory :ambassadorship do
      role { "member" }
      organization { FactoryBot.create(:ambassador_organization) }
      user { FactoryBot.create(:user) }
    end
  end
end
