module Organized
  class AmbassadorsController < Organized::BaseController
    def index
      @ambassadors =
        Ambassador
          .decorate(current_organization.users.limit(10))
          .sort_by { |ambassador| -ambassador.progress }

      @tasks = current_user.ambassador_tasks
    end
  end
end
