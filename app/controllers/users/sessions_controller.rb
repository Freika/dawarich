# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  before_action :load_invitation_context, only: [:new]
  before_action :check_email_password_login_allowed, only: [:create]

  def new
    super
  end

  private

  def check_email_password_login_allowed
    return unless DawarichSettings.oidc_enabled?
    return if DawarichSettings.registration_enabled?

    redirect_to root_path, alert: 'Email/password login is disabled. Please use OIDC to sign in.'
  end

  def load_invitation_context
    return if invitation_token.blank?

    @invitation = Family::Invitation.find_by(token: invitation_token)
    # Store token in session so it persists through the sign-in process
    session[:invitation_token] = invitation_token if invitation_token.present?
  end

  def invitation_token
    @invitation_token ||= params[:invitation_token] || session[:invitation_token]
  end
end
