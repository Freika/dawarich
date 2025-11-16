class MapsV2Controller < ApplicationController
  before_action :authenticate_user!

  def index
    # Default to current month
    @start_date = Date.today.beginning_of_month
    @end_date = Date.today.end_of_month
  end
end
