class AmbassadorTask < ActiveRecord::Base
  has_many :ambassador_task_assignments
  has_many :users, through: :ambassador_task_assignments

  validates :description, uniqueness: true
end
