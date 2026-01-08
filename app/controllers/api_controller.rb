# frozen_string_literal: true

class ApiController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_version_header
  before_action :authenticate_api_key

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  private

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

  def authenticate_active_api_user!
    if current_api_user.nil?
      render json: { error: 'User account is not active or has been deleted' }, status: :unauthorized
      return false
    end

    unless current_api_user.active_until&.future?
      render json: { error: 'User subscription is not active' }, status: :unauthorized
      return false
    end

    true
  end

  def current_api_user
    @current_api_user ||= begin
      user = User.active_accounts.find_by(api_key:)
      user if user&.active_for_authentication?
    end
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
end
