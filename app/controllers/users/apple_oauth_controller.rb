# frozen_string_literal: true

class Users::AppleOauthController < ApplicationController
  include PendingImportClaimable

  skip_before_action :verify_authenticity_token, only: :callback
  before_action :ensure_enabled

  COOKIE_TTL = 10.minutes
  COOKIE_OPTS = { httponly: true, same_site: :none, secure: true }.freeze

  def request_phase
    nonce = SecureRandom.hex(32)
    state = SecureRandom.hex(32)

    cookies.encrypted[:apple_oauth_nonce] = COOKIE_OPTS.merge(value: nonce, expires: COOKIE_TTL.from_now)
    cookies.encrypted[:apple_oauth_state] = COOKIE_OPTS.merge(value: state, expires: COOKIE_TTL.from_now)

    # Apple's callback is a cross-site form POST, so the SameSite=Lax session
    # cookie won't accompany it. Relay the pending-import ticket through an
    # encrypted SameSite=None cookie, same as the nonce/state above.
    if session[:pending_import_ticket].present?
      cookies.encrypted[:apple_pending_import_ticket] =
        COOKIE_OPTS.merge(value: session[:pending_import_ticket], expires: COOKIE_TTL.from_now)
    end

    redirect_to authorize_url(nonce: nonce, state: state), allow_other_host: true
  end

  def callback
    expected_state = cookies.encrypted[:apple_oauth_state]
    expected_nonce = cookies.encrypted[:apple_oauth_nonce]
    restore_pending_import_ticket
    cookies.delete(:apple_oauth_state)
    cookies.delete(:apple_oauth_nonce)

    return handle_apple_error if params[:error].present?

    return reject_with(state_mismatch_message) if expected_state.blank?

    submitted_state = params[:state].to_s
    return reject_with(state_mismatch_message) unless states_equal?(expected_state, submitted_state)

    claims = Auth::VerifyAppleToken
             .new(params[:id_token], nonce: expected_nonce, client_id: ENV['APPLE_WEB_SERVICES_ID'])
             .call

    user, _created = Auth::FindOrCreateOauthUser.new(
      provider: 'apple',
      provider_label: I18n.t('oauth_providers.sign_in_with_apple'),
      claims: claims,
      email_verified: [true, 'true'].include?(claims[:email_verified]),
      name_attrs: extract_name_from_params
    ).call

    flash[:notice] = I18n.t('devise.omniauth_callbacks.success', kind: I18n.t('oauth_providers.apple'))
    sign_in_and_redirect user, event: :authentication
  rescue Auth::VerifyAppleToken::InvalidToken => e
    reject_with(I18n.t('controllers.users.apple_oauth.sign_in_failed', message: e.message))
    capture_apple_breadcrumb('invalid_token', extra: { message: e.message })
  rescue Auth::FindOrCreateOauthUser::LinkVerificationSent => e
    session[:pending_oauth_link] = {
      'user_id' => e.user.id,
      'provider' => e.provider,
      'uid' => e.uid,
      'provider_label' => I18n.t('oauth_providers.sign_in_with_apple'),
      'expires_at' => 15.minutes.from_now.to_i
    }
    redirect_to auth_account_link_challenge_path
    capture_apple_breadcrumb('link_verification_sent', extra: { user_id: e.user.id, uid: e.uid })
  rescue Auth::FindOrCreateOauthUser::UnverifiedEmail
    reject_with(I18n.t('controllers.users.apple_oauth.email_not_verified'))
    capture_apple_breadcrumb('unverified_email')
  rescue Auth::FindOrCreateOauthUser::AccountPendingDeletion
    reject_with(I18n.t('controllers.users.apple_oauth.account_pending_deletion'))
    capture_apple_breadcrumb('account_pending_deletion')
  rescue Auth::FindOrCreateOauthUser::MissingOauthEmail => e
    reject_with(
      I18n.t('controllers.users.apple_oauth.missing_email')
    )
    capture_apple_breadcrumb('missing_email', level: :warning, extra: { uid: e.uid })
  end

  protected

  def after_sign_in_path_for(resource)
    claim_pending_import_for(resource)
    super
  end

  private

  def restore_pending_import_ticket
    ticket = cookies.encrypted[:apple_pending_import_ticket]
    cookies.delete(:apple_pending_import_ticket)
    return if ticket.blank?

    session[:pending_import_ticket] ||= ticket
  end

  def ensure_enabled
    head :not_found unless APPLE_WEB_SIGN_IN_ENABLED
  end

  def authorize_url(nonce:, state:)
    params = {
      client_id: ENV['APPLE_WEB_SERVICES_ID'],
      redirect_uri: callback_redirect_uri,
      response_type: 'code id_token',
      response_mode: 'form_post',
      scope: 'name email',
      state: state,
      nonce: Digest::SHA256.hexdigest(nonce)
    }
    "https://appleid.apple.com/auth/authorize?#{params.to_query}"
  end

  def callback_redirect_uri
    ENV.fetch('APPLE_WEB_REDIRECT_URI')
  end

  def extract_name_from_params
    return {} if params[:user].blank?

    parsed = JSON.parse(params[:user])
    return {} unless parsed.is_a?(Hash)

    name = parsed['name']
    return {} unless name.is_a?(Hash)

    { first_name: name['firstName'], last_name: name['lastName'] }
  rescue JSON::ParserError
    {}
  end

  def handle_apple_error
    if params[:error].to_s == 'user_cancelled_authorize'
      redirect_to new_user_session_path,
                  notice: I18n.t('controllers.users.apple_oauth.sign_in_with_apple_was_cancelled')
    else
      capture_apple_breadcrumb('authorize_error', extra: { error: params[:error].to_s })
      reject_with(I18n.t('controllers.users.apple_oauth.did_not_complete'))
    end
  end

  def reject_with(message)
    redirect_to new_user_session_path, alert: message
  end

  def state_mismatch_message
    I18n.t('controllers.users.apple_oauth.state_mismatch')
  end

  def states_equal?(expected, submitted)
    return false unless expected.bytesize == submitted.bytesize

    ActiveSupport::SecurityUtils.secure_compare(expected, submitted)
  end

  def capture_apple_breadcrumb(reason, level: :info, extra: {})
    return unless defined?(Sentry)

    Sentry.capture_message(
      "apple_web_sign_in.#{reason}",
      level: level,
      extra: extra
    )
  rescue StandardError
    nil
  end
end
