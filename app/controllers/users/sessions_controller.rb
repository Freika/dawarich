# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  include PendingImportClaimable

  before_action :load_invitation_context, only: [:new]
  prepend_before_action :check_otp_required, only: [:create]
  prepend_before_action :check_email_password_login_allowed, only: [:create]

  def new
    attempted = take_oidc_auto_login_attempt
    return super unless oidc_auto_login?(attempted)

    session[:oidc_auto_login_attempted] = true unless prefetch_request?
    render :oidc_auto_login
  end

  protected

  def after_sign_in_path_for(resource)
    claim_pending_import_for(resource)
    super
  end

  private

  def check_otp_required
    return unless request.post?
    return if DawarichSettings.oidc_enabled? && !ALLOW_EMAIL_PASSWORD_LOGIN
    return unless DawarichSettings.two_factor_available?
    return if params.dig(:user, :email).blank?

    user = User.find_by(email: params[:user][:email])
    return unless user&.otp_required_for_login?
    return unless user.valid_password?(params[:user][:password])

    session[:otp_user_id] = user.id
    session[:otp_challenge_at] = Time.current.to_i
    session[:otp_remember_me] = params.dig(:user, :remember_me) == '1'
    self.resource = user
    render :otp_challenge, status: :unprocessable_entity
  end

  def check_email_password_login_allowed
    return unless DawarichSettings.oidc_enabled?
    return if ALLOW_EMAIL_PASSWORD_LOGIN

    redirect_to root_path,
                alert: I18n.t('controllers.users.sessions.email_password_login_is_disabled_please_use_oidc_to_sign')
  end

  # One automatic attempt per visit: the flag set before handing off to the
  # identity provider is consumed by the next visit, so any return to the
  # sign-in page (failed callback, abandoned login, back button) shows the
  # page instead of bouncing straight back to the provider. Prefetches (Turbo
  # hover, browser speculation) only read the flag; a real visit consumes it.
  def take_oidc_auto_login_attempt
    return session[:oidc_auto_login_attempted] if prefetch_request?

    session.delete(:oidc_auto_login_attempted)
  end

  def oidc_auto_login?(attempted)
    DawarichSettings.oidc_auto_login_enabled? &&
      !attempted &&
      params[:auto_login] != 'false' &&
      invitation_token.blank?
  end

  def load_invitation_context
    return if invitation_token.blank?

    @invitation = Family::Invitation.find_by(token: invitation_token)
    session[:invitation_token] = invitation_token if invitation_token.present?
  end

  def invitation_token
    @invitation_token ||= params[:invitation_token] || session[:invitation_token]
  end
end
