# frozen_string_literal: true

class Api::V1::ResidencyController < ApiController
  before_action :require_pro_api!

  def show
    year = params[:year]&.to_i || Residency::DayCounter.default_year(current_api_user)

    result = Residency::DayCounter.new(current_api_user, year).call

    render json: result
  end
end
