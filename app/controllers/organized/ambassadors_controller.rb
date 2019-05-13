module Organized
  class AmbassadorsController < Organized::BaseController
    def index
      @ambassadors = User.ambassadors(organization: current_organization)
      @tasks = []
    end
  end
end
