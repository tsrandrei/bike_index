require "spec_helper"

describe AmbassadorTask, type: :model do
  it { is_expected.to respond_to(:description) }
  it { is_expected.to respond_to(:users) }

  it { is_expected.to have_many(:users) }
  it { is_expected.to have_many(:ambassador_task_assignments) }

  it { is_expected.to validate_uniqueness_of(:description) }
end
