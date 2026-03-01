# frozen_string_literal: true

class ApiController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_version_header
  before_action :authenticate_api_key

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

  def require_pro_or_self_hosted_api!
    return if current_api_user&.pro_or_self_hosted?

    render json: {
      error: 'pro_plan_required',
      message: 'This feature requires a Pro plan.',
      upgrade_url: 'https://dawarich.app/pricing'
    }, status: :forbidden
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

  # Returns points scoped to the user's plan data window.
  # Lite users see only 12 months; Pro/self_hoster see everything.
  def scoped_points(user = current_api_user)
    points = user.points
    points = points.where('timestamp >= ?', 12.months.ago.to_i) if user.lite?
    points
  end

  # Returns only archived points (older than 12 months) for Lite users.
  # Pro and self-hoster users have no archived concept — returns none.
  def archived_points(user = current_api_user)
    return user.points.none unless user.lite?

    user.points.where('timestamp < ?', 12.months.ago.to_i)
  end
end
