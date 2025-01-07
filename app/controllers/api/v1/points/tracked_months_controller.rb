# frozen_string_literal: true

class Api::V1::Points::TrackedMonthsController < ApiController
  def index
    render json: current_api_user.years_tracked
  end
end
