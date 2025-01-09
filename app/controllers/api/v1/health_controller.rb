# frozen_string_literal: true

class Api::V1::HealthController < ApiController
  skip_before_action :authenticate_api_key

  def index
    response.set_header('X-Dawarich-Response', 'Hey, I\'m alive!')
    render json: { status: 'ok' }
  end
end
