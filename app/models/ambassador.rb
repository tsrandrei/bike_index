class Ambassador < SimpleDelegator
  def self.all
    User.ambassadors
  end

  def self.decorate(user)
    Array(user).map { |u| new(u) }
  end

  def progress
    task_assignments =
      AmbassadorTaskAssignment.where(user_id: id)
    0.5
  end
end
