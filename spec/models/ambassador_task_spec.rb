require "spec_helper"

describe AmbassadorTask, type: :model do
  it { is_expected.to respond_to(:description) }
  it { is_expected.to respond_to(:completed) }
  it { is_expected.to respond_to(:users) }
end
