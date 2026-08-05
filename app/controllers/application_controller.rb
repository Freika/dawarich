# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  around_action :switch_locale
  before_action :sign_out_deleted_users
  before_action :configure_permitted_parameters, if: :devise_controller?
  around_action :set_user_time_zone
  before_action :unread_notifications, :set_self_hosted_status, :store_client_header

  helper_method :current_user_safe_settings, :poster_ordering_enabled?, :family_feature_available?,
                :current_user_features, :family_home_path, :alternate_locale, :locale_switch_path

  # Memoized per-request SafeSettings for the current user. Use this instead of
  # `current_user.safe_settings` in partials/helpers that may render many rows
  # — User#safe_settings allocates a fresh deep_dup'd hash on every call.
  def current_user_safe_settings
    @current_user_safe_settings ||= current_user&.safe_settings
  end

  # Memoized per request: the map serializes the whole hash and the navbar asks
  # for the family flag twice; one plan lookup serves all of them.
  def current_user_features
    @current_user_features ||= DawarichSettings.features_for(current_user)
  end

  def family_feature_available?
    current_user_features[:family]
  end

  # Where "back to the family" should land: the family page while the plan is
  # active, the lapsed/upgrade panel when it is not — going through the gated
  # #show would bounce and overwrite the flash.
  def family_home_path
    family_feature_available? ? family_path : new_family_path
  end

  # Ordering is on unless this instance turned the flag off, so an install
  # that never registered the flag — or lost it — still offers prints rather
  # than silently hiding a shipped feature.
  def poster_ordering_enabled?
    return true unless Flipper.exist?(:poster_ordering)

    Flipper.enabled?(:poster_ordering, current_user)
  rescue StandardError => e
    Rails.logger.warn("[poster_ordering] Flipper unavailable: #{e.class}: #{e.message}")
    true
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_in, keys: [:otp_attempt])
  end

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

    redirect_to root_path, notice: I18n.t('controllers.application.your_account_is_not_active'), status: :see_other
  end

  def authenticate_non_self_hosted!
    return unless DawarichSettings.self_hosted?

    user_not_authorized
  end

  def after_sign_in_path_for(resource)
    return trial_resume_path if resource.respond_to?(:pending_payment?) && resource.pending_payment?

    # Check for family invitation first
    invitation_token = params[:invitation_token] || session[:invitation_token]
    if invitation_token.present?
      invitation = Family::Invitation.find_by(token: invitation_token)
      return family_invitation_path(invitation.token) if invitation&.can_be_accepted?
    end

    # Handle mobile client flow (iOS and Android)
    client_type = request.headers['X-Dawarich-Client'] || session[:dawarich_client]

    case client_type
    when 'ios', 'android'
      payload = { api_key: resource.api_key, exp: 5.minutes.from_now.to_i }

      token = Subscription::EncodeJwtToken.new(
        payload, Auth::MobileHandoffSecret.call
      ).call

      ios_success_path(token:)
    else
      super
    end
  end

  def require_pro!
    return if DawarichSettings.self_hosted?

    unless current_user
      respond_to do |format|
        format.html do
          redirect_to new_user_session_path, alert: I18n.t('controllers.application.please_sign_in_to_continue'),
         status: :see_other
        end
        format.json do
          render json: { error: I18n.t('controllers.application.you_need_to_sign_in_first') }, status: :unauthorized
        end
        format.turbo_stream do
          redirect_to new_user_session_path, alert: I18n.t('controllers.application.please_sign_in_to_continue'),
status: :see_other
        end
      end
      return
    end

    return if current_user.full_access?

    respond_to do |format|
      format.html do
        redirect_back fallback_location: root_path,
                      alert: I18n.t('controllers.application.this_feature_requires_a_pro_plan'),
                      status: :see_other
      end
      format.json do
        render json: { error: I18n.t('controllers.application.this_feature_requires_a_pro_plan') }, status: :forbidden
      end
      format.turbo_stream do
        redirect_back fallback_location: root_path,
                      alert: I18n.t('controllers.application.this_feature_requires_a_pro_plan'),
                      status: :see_other
      end
    end
  end

  # Family routes exist on every instance; access is decided per user. Send web
  # visitors to the family landing page, which explains the plan and carries the
  # upgrade link. Api::V1 controllers override this with a JSON-only response.
  def ensure_family_feature_available!
    return if family_feature_available?

    message = I18n.t('controllers.application.family_plan_required')
    respond_to do |format|
      format.html { redirect_to new_family_path, alert: message, status: :see_other }
      format.turbo_stream do
        redirect_to new_family_path, alert: message, status: :see_other
      end
      format.json do
        render json: { error: 'family_plan_required', message: message },
               status: :forbidden
      end
    end
  end

  private

  def switch_locale(&action)
    parameter_locale = supported_locale(params[:locale])
    remember_locale(parameter_locale) if parameter_locale && !prefetch_request?
    locale = parameter_locale || current_user&.preferred_locale || supported_locale(session[:locale]) ||
             locale_from_accept_language || I18n.default_locale

    I18n.with_locale(locale, &action)
  end

  # A prefetched response is still rendered in the requested language so the
  # preview matches what a click would show; only the choice is withheld until
  # the user actually navigates.
  def remember_locale(locale)
    session[:locale] = locale.to_s
    persist_user_locale(locale)
  end

  def supported_locale(value)
    locale = value.to_s.downcase.to_sym
    locale if I18n.available_locales.include?(locale)
  end

  def locale_from_accept_language
    candidates = request.headers['Accept-Language'].to_s.split(',').each_with_index.filter_map do |language, index|
      locale_tag, *parameters = language.split(';').map(&:strip)
      locale = supported_locale(locale_tag.to_s.split('-').first)
      quality = parameters.find { |parameter| parameter.start_with?('q=') }&.delete_prefix('q=')&.to_f || 1.0
      [locale, quality, index] if locale && quality.positive?
    end

    candidates.max_by { |_locale, quality, index| [quality, -index] }&.first
  end

  def alternate_locale
    I18n.locale == :de ? :en : :de
  end

  # Built from `request.path` rather than `url_for` so that query parameters
  # never reach route generation: `?host=`, `?controller=` and `?action=` would
  # otherwise send the link off-site or raise on every page carrying the navbar.
  # Non-GET requests fall back to the root path because a re-rendered form sits
  # on a path that only answers to POST/PATCH.
  def locale_switch_path
    return "#{root_path}?#{{ 'locale' => alternate_locale.to_s }.to_query}" unless request.get?

    query = request.query_parameters.merge('locale' => alternate_locale.to_s)

    "#{request.path}?#{query.to_query}"
  end

  def persist_user_locale(locale)
    return unless current_user
    return if current_user.preferred_locale == locale

    current_user.persist_locale!(locale)
  end

  # Turbo Drive prefetches links on hover, so a pointer passing over the switch
  # link would otherwise save a language the user never chose.
  def prefetch_request?
    request.headers['Sec-Purpose'].to_s.include?('prefetch') ||
      request.headers['X-Sec-Purpose'].to_s.include?('prefetch') ||
      request.headers['Purpose'].to_s.include?('prefetch') ||
      request.headers['X-Moz'].to_s.casecmp?('prefetch')
  end

  def sign_out_deleted_users
    return unless current_user&.deleted?

    sign_out current_user
    redirect_to root_path, alert: I18n.t('controllers.application.your_account_has_been_deleted')
  end

  def set_user_time_zone(&block)
    if current_user
      timezone = current_user.timezone
      Time.use_zone(timezone, &block)
    else
      yield
    end
  rescue ArgumentError
    yield
  end

  def set_self_hosted_status
    @self_hosted = DawarichSettings.self_hosted?
  end

  ALLOWED_CLIENTS = %w[ios android].freeze

  def store_client_header
    client = request.headers['X-Dawarich-Client'] || params[:client]
    return unless client
    return unless ALLOWED_CLIENTS.include?(client)

    session[:dawarich_client] = client
  end

  def user_not_authorized
    redirect_back fallback_location: root_path,
                  alert: I18n.t('controllers.application.you_are_not_authorized_to_perform_this_action'),
                  status: :see_other
  end
end
