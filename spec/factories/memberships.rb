FactoryBot.define do
  factory :membership do
    role { "member" }
    organization { FactoryBot.create(:organization) }
    factory :existing_membership do
      user { FactoryBot.create(:user) }
    end
  end

  factory :ambassadorship do
    role { "ambassador_group" }
    organization { FactoryBot.create(:organization) }
    user { FactoryBot.create(:user) }
  end
end
