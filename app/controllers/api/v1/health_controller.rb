# frozen_string_literal: true

class Api::V1::HealthController < ApiController
  skip_before_action :authenticate_api_key
  skip_before_action :reject_pending_payment!, only: :ready
  skip_after_action :set_rate_limit_headers, only: :ready

  def index
    render json: { status: 'ok' }
  end

  def ready
    ActiveRecord::Base.connection.select_value('SELECT 1')
    Sidekiq.redis { |redis| redis.call('PING') }

    render json: { status: 'ok' }
  rescue StandardError => e
    Rails.logger.warn("Readiness check failed: #{e.class}")
    render json: { status: 'unavailable' }, status: :service_unavailable
  end
end
