# frozen_string_literal: true

class ApiController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_version_header
  before_action :authenticate_api_key
  after_action :set_rate_limit_headers

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  private

  def set_user_time_zone(&block)
    if current_api_user
      timezone = current_api_user.timezone
      Time.use_zone(timezone, &block)
    else
      yield
    end
  rescue ArgumentError
    yield
  end

  def record_not_found
    render json: { error: 'Record not found' }, status: :not_found
  end

  def set_version_header
    message = "Hey, I\'m alive#{current_api_user ? ' and authenticated' : ''}!"

    response.set_header('X-Dawarich-Response', message)
    response.set_header('X-Dawarich-Version', APP_VERSION)
  end

  def authenticate_api_key
    return head :unauthorized unless current_api_user

    true
  end

  def require_pro_api!
    return if DawarichSettings.self_hosted?
    return if current_api_user&.pro?

    render json: {
      error: 'pro_plan_required',
      message: 'This feature requires a Pro plan.',
      upgrade_url: 'https://dawarich.app/pricing'
    }, status: :forbidden
  end

  def require_write_api!
    return if DawarichSettings.self_hosted?
    return if current_api_user&.pro?

    render json: {
      error: 'write_api_restricted',
      message: 'Write API access requires a Pro plan. Your data was not modified.',
      upgrade_url: 'https://dawarich.app/pricing'
    }, status: :forbidden
  end

  # Returns points scoped to the user's plan data window.
  # Lite users see only the last 12 months; Pro users see everything.
  def scoped_points(user = current_api_user)
    points = user.points
    points = points.where('timestamp >= ?', 12.months.ago.to_i) if user.lite?
    points
  end

  def authenticate_active_api_user!
    if current_api_user.nil?
      render json: { error: 'User account is not active or has been deleted' }, status: :unauthorized

      return false
    end

    if current_api_user.active_until&.past?
      render json: { error: 'User subscription is not active' }, status: :unauthorized

      return false
    end

    true
  end

  def current_api_user
    @current_api_user ||= User.find_by(api_key:)
  end

  def api_key
    params[:api_key] || request.headers['Authorization']&.split(' ')&.last
  end

  def validate_params
    missing_params = required_params.select { |param| params[param].blank? }

    if missing_params.any?
      render json: {
        error: "Missing required parameters: #{missing_params.join(', ')}"
      }, status: :bad_request and return
    end

    params.permit(*required_params)
  end

  def required_params
    []
  end

  def validate_points_limit
    limit_exceeded = PointsLimitExceeded.new(current_api_user).call

    render json: { error: 'Points limit exceeded' }, status: :unauthorized if limit_exceeded
  end

  def set_rate_limit_headers
    return unless current_api_user
    return if DawarichSettings.self_hosted?

    throttle_data = request.env['rack.attack.throttle_data']&.dig('api/token')
    return unless throttle_data

    limit = throttle_data[:limit]
    count = throttle_data[:count]
    period = throttle_data[:period]
    now = Time.zone.now.to_i

    response.set_header('X-RateLimit-Limit', limit.to_s)
    response.set_header('X-RateLimit-Remaining', [limit - count, 0].max.to_s)
    response.set_header('X-RateLimit-Reset', (now + (period - (now % period))).to_s)
  end
end
