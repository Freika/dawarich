# frozen_string_literal: true

class Api::V1::HealthController < ApiController
  skip_before_action :authenticate_api_key

  def index
    if current_api_user
      response.set_header('X-Dawarich-Response', 'Hey, I\'m alive and authenticated!')
    else
      response.set_header('X-Dawarich-Response', 'Hey, I\'m alive!')
    end

    render json: { status: 'ok' }
  end
end
