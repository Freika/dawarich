# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  before_action :load_invitation_context, only: [:new]
  before_action :check_email_password_login_allowed, only: [:create]
  prepend_before_action :check_otp_required, only: [:create]

  def new
    super
  end

  private

  def after_sign_in_path_for(resource)
    return trial_resume_path if resource.pending_payment?

    super
  end

  def check_otp_required
    return unless request.post?
    return unless DawarichSettings.two_factor_available?
    return if params.dig(:user, :email).blank?

    user = User.find_by(email: params[:user][:email])
    return unless user&.otp_required_for_login?
    return unless user.valid_password?(params[:user][:password])

    session[:otp_user_id] = user.id
    session[:otp_challenge_at] = Time.current.to_i
    self.resource = user
    render :otp_challenge, status: :unprocessable_entity
  end

  def check_email_password_login_allowed
    return unless DawarichSettings.oidc_enabled?
    return if DawarichSettings.registration_enabled?

    redirect_to root_path, alert: 'Email/password login is disabled. Please use OIDC to sign in.'
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
