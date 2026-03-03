# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  include UtmTrackable

  before_action :set_invitation, only: %i[new create]
  before_action :check_registration_allowed, only: %i[new create]
  before_action :store_utm_params, only: %i[new], unless: -> { DawarichSettings.self_hosted? }

  def new
    build_resource({})

    resource.email = @invitation.email if @invitation

    yield resource if block_given?

    respond_with resource
  end

  def create
    super do |resource|
      if resource.persisted?
        assign_utm_params(resource)
        accept_invitation_for_user(resource) if @invitation
      end
    end
  end

  def destroy
    unless resource.can_delete_account?
      set_flash_message! :alert, :cannot_delete
      redirect_to edit_user_registration_path, status: :unprocessable_content
      return
    end

    Users::DestroyJob.perform_later(resource.id) if resource.mark_as_deleted_atomically!

    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)

    set_flash_message! :notice, :destroyed
    yield resource if block_given?
    respond_with_navigational(resource) { redirect_to after_sign_out_path_for(resource_name) }
  end

  protected

  def after_sign_up_path_for(resource)
    return family_path if @invitation&.family

    super(resource)
  end

  def after_inactive_sign_up_path_for(resource)
    return family_path if @invitation&.family

    super(resource)
  end

  private

  def check_registration_allowed
    return unless self_hosted_mode?

    # When OIDC is enabled and email/password registration is disabled,
    # block all email/password registration including family invitations
    if oidc_only_mode?
      redirect_to root_path,
                  alert: 'Email/password registration is disabled. Please use OIDC to sign in.'
      return
    end

    return if valid_invitation_token?
    return if email_password_registration_allowed?

    redirect_to root_path,
                alert: 'Registration is not available. Please contact your administrator for access.'
  end

  def set_invitation
    return if invitation_token.blank?

    @invitation = Family::Invitation.find_by(token: invitation_token)
  end

  def self_hosted_mode?
    DawarichSettings.self_hosted?
  end

  def valid_invitation_token?
    @invitation&.can_be_accepted?
  end

  def invitation_token
    @invitation_token ||= params[:invitation_token] ||
                          params.dig(:user, :invitation_token) ||
                          session[:invitation_token]
  end

  def accept_invitation_for_user(user)
    return unless @invitation&.can_be_accepted?

    service = Families::AcceptInvitation.new(
      invitation: @invitation,
      user: user
    )

    if service.call
      flash[:notice] = "Welcome to #{@invitation.family.name}! You're now part of the family."
    else
      flash[:alert] =
        "Account created successfully, but there was an issue accepting the invitation: #{service.error_message}"
    end
  rescue StandardError => e
    Rails.logger.error "Error accepting invitation during registration: #{e.message}"
    flash[:alert] =
      'Account created successfully, but there was an issue accepting the invitation. Please try accepting it again.'
  end

  def sign_up_params
    super
  end

  def email_password_registration_allowed?
    ALLOW_EMAIL_PASSWORD_REGISTRATION
  end

  def oidc_only_mode?
    DawarichSettings.oidc_enabled? && !email_password_registration_allowed?
  end
end
