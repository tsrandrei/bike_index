FactoryBot.define do
  factory :ambassador_task_assignment do
    user { FactoryBot.create(:user_ambassador) }
    ambassador_task { FactoryBot.create(:ambassador_task) }
  end
end
