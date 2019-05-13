module Organized
  class AmbassadorsController < Organized::BaseController
    def index
      @ambassadors = User.ambassadors(organization: current_organization)
    end
  end
end
