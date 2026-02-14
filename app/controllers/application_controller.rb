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
    # Check for family invitation first
    invitation_token = params[:invitation_token] || session[:invitation_token]
    if invitation_token.present?
      invitation = Family::Invitation.find_by(token: invitation_token)
      return family_invitation_path(invitation.token) if invitation&.can_be_accepted?
    end

    # Handle iOS client flow
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
    user = current_user || (respond_to?(:current_api_user, true) && current_api_user)
    return if user&.family_feature_available?

    respond_to do |format|
      format.html { redirect_to root_path, alert: 'Family feature requires a Family plan.' }
      format.json { render json: { error: 'Family plan required' }, status: :forbidden }
    end
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
