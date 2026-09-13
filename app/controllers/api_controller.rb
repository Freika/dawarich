# frozen_string_literal: true

class ApiController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_version_header
  before_action :authenticate_api_key
  before_action :reject_pending_payment!
  after_action :set_rate_limit_headers

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  private

  # API payloads are a machine contract, not UI copy. Clients send their device
  # `Accept-Language`, which would otherwise translate every error and message
  # string and break anyone matching on them.
  def switch_locale(&block)
    I18n.with_locale(I18n.default_locale, &block)
  end

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
    render json: { error: I18n.t('controllers.api.record_not_found') }, status: :not_found
  end

  def set_version_header
    authenticated = api_key.present? && current_api_user.present?
    message = "Hey, I'm alive#{authenticated ? ' and authenticated' : ''}!"

    response.set_header('X-Dawarich-Response', message)
    response.set_header('X-Dawarich-Version', APP_VERSION)
  end

  def authenticate_api_key
    return head :unauthorized unless current_api_user

    true
  end

  # Users in :pending_payment have signed up but not yet completed checkout
  # (mobile OAuth flow). Block all API access except the auth endpoints
  # (which skip this filter via Api::V1::Auth::BaseController) and the
  # destroy endpoint (which skips this filter explicitly).
  def reject_pending_payment!
    return unless current_api_user&.pending_payment?

    render json: {
      error: 'payment_required',
      message: I18n.t('controllers.api.complete_your_subscription_to_continue'),
      resume_url: upgrade_url_for(current_api_user)
    }, status: :payment_required
  end

  def require_pro_api!
    return unless current_api_user # auth already handled by authenticate_api_key
    return if current_api_user.entitlements.pro_api?

    render json: {
      error: 'pro_plan_required',
      message: I18n.t('controllers.api.this_feature_requires_a_pro_plan'),
      upgrade_url: upgrade_url_for(current_api_user)
    }, status: :forbidden
  end

  def require_write_api!
    return unless current_api_user # auth already handled by authenticate_api_key
    return if current_api_user.entitlements.write_api?

    render json: {
      error: 'write_api_restricted',
      message: I18n.t('controllers.api.write_api_access_requires_a_pro_plan_your_data_was'),
      upgrade_url: upgrade_url_for(current_api_user)
    }, status: :forbidden
  end

  # API clients authenticate with an api_key rather than a session, so the plan
  # check has to look at current_api_user instead of current_user.
  def ensure_family_feature_available!
    return unless current_api_user # auth already handled by authenticate_api_key
    return if DawarichSettings.family_feature_available_for?(current_api_user)

    render json: {
      error: 'family_plan_required',
      message: I18n.t('controllers.application.family_plan_required'),
      upgrade_url: upgrade_url_for(current_api_user)
    }, status: :forbidden
  end

  # Returns points scoped to the user's plan data window.
  # Delegates to PlanScopable concern on User model.
  def scoped_points(user = current_api_user)
    user.scoped_points
  end

  # Applies the 12-month plan window to any point relation.
  # Use this when scoping points that don't start from user.points (e.g. track.points).
  def apply_plan_scope(relation, user = current_api_user)
    window_start = user&.entitlements&.data_window_start
    return relation unless window_start

    relation.where('timestamp >= ?', window_start.to_i)
  end

  def upgrade_url_for(user)
    return nil if DawarichSettings.self_hosted?

    "#{MANAGER_URL}/auth/dawarich?token=#{user.generate_subscription_token}"
  end

  def authenticate_active_api_user!
    if current_api_user.nil?
      render json: { error: I18n.t('controllers.api.user_account_is_not_active_or_has_been_deleted') },
             status: :unauthorized

      return false
    end

    if current_api_user.inactive?
      render json: { error: I18n.t('controllers.api.user_account_is_not_active') }, status: :unauthorized

      return false
    end

    if current_api_user.active_until&.past?
      render json: { error: I18n.t('controllers.api.user_subscription_is_not_active') }, status: :unauthorized

      return false
    end

    true
  end

  def current_api_user
    @current_api_user ||= User.find_by(api_key:)
  end

  def api_key
    params[:api_key] || extract_bearer_token
  end

  def extract_bearer_token
    header = request.headers['Authorization'].to_s
    match = header.match(/\ABearer\s+(\S+)\z/i)
    match && match[1]
  end

  def validate_params
    missing_params = required_params.select { |param| params[param].blank? }

    if missing_params.any?
      render json: {
        error: I18n.t('controllers.api.missing_required_parameters_join', parameters: missing_params.join(', '))
      }, status: :bad_request and return
    end

    params.permit(*required_params)
  end

  def required_params
    []
  end

  def validate_points_limit
    limit_exceeded = PointsLimitExceeded.new(current_api_user).call

    render json: { error: I18n.t('controllers.api.points_limit_exceeded') }, status: :unauthorized if limit_exceeded
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
