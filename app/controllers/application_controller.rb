# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  before_action :unread_notifications, :set_self_hosted_status, :store_client_header

  protected

  def unread_notifications
    return [] unless current_user

    @unread_notifications ||= Notification.where(user: current_user).unread
  end

  def authenticate_admin!
    return if current_user&.admin?

    user_not_authorized
  end

  def authenticate_self_hosted!
    return if DawarichSettings.self_hosted?

    user_not_authorized
  end

  def authenticate_active_user!
    return if current_user&.active_until&.future?

    redirect_to root_path, notice: 'Your account is not active.', status: :see_other
  end

  def authenticate_non_self_hosted!
    return unless DawarichSettings.self_hosted?

    user_not_authorized
  end

  def after_sign_in_path_for(resource)
    client_type = request.headers['X-Dawarich-Client'] || session[:dawarich_client]

    case client_type
    when 'ios'
      payload = { api_key: resource.api_key, exp: 5.minutes.from_now.to_i }

      token = Subscription::EncodeJwtToken.new(
        payload, ENV['AUTH_JWT_SECRET_KEY']
      ).call

      ios_success_path(token:)
    else
      super
    end
  end

  def ensure_family_feature_enabled!
    return if DawarichSettings.family_feature_enabled?

    render json: { error: 'Family feature is not enabled' }, status: :forbidden
  end

  private

  def set_self_hosted_status
    @self_hosted = DawarichSettings.self_hosted?
  end

  def store_client_header
    return unless request.headers['X-Dawarich-Client']

    session[:dawarich_client] = request.headers['X-Dawarich-Client']
  end

  def user_not_authorized
    redirect_back fallback_location: root_path,
                  alert: 'You are not authorized to perform this action.',
                  status: :see_other
  end
end
