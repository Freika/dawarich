# frozen_string_literal: true

class Api::V1::HealthController < ApiController
  skip_before_action :authenticate_api_key

  def index
    render json: { status: 'ok' }
  end
end
