# frozen_string_literal: true

class Api::V1::StatsController < ApiController
  def index
    render json: StatsSerializer.new(current_api_user).call
  end
end
