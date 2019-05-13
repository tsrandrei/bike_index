module Organized
  class AmbassadorsController < Organized::BaseController
    include SortableTable

    def index
    end

    def stolen_bikes
      @page = params[:page] || 1
      @per_page = params[:per_page] || 25
      @bikes = Bike.stolen.page(@page).per(@per_page)
    end
  end
end
