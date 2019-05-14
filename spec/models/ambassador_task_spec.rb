require "spec_helper"

describe AmbassadorTask, type: :model do
  it { is_expected.to respond_to(:description) }
  it { is_expected.to respond_to(:completed) }
  it { is_expected.to respond_to(:user) }
  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:user) }

  describe "validates the associated user is an ambassador" do
    context "given a non-ambassador" do
      it "is invalid" do
        user = FactoryBot.create(:user)
        task = AmbassadorTask.new(user: user)
        expect(task).to be_invalid
        expect(task.errors[:user]).to eq(["must be an ambassador"])
      end
    end

    context "given an ambassador" do
      it "is valid" do
        ambassador = FactoryBot.create(:ambassador)
        task = AmbassadorTask.new(user: ambassador)
        expect(task).to be_valid
      end
    end
  end
end
