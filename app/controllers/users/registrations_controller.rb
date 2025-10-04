# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  before_action :check_registration_allowed, only: [:new, :create]
  before_action :set_invitation, only: [:new, :create]

  def new
    build_resource({})

    resource.email = @invitation.email if @invitation

    yield resource if block_given?

    respond_with resource
  end

  def create
    super do |resource|
      if resource.persisted? && @invitation
        accept_invitation_for_user(resource)
      end
    end
  end

  protected

  def after_sign_up_path_for(resource)
    if @invitation&.family
      family_path(@invitation.family)
    else
      super(resource)
    end
  end

  def after_inactive_sign_up_path_for(resource)
    if @invitation&.family
      family_path(@invitation.family)
    else
      super(resource)
    end
  end

  private

  def check_registration_allowed
    return true if DawarichSettings.self_hosted?
    return true if valid_invitation_token?

    redirect_to root_path, alert: 'Registration is not available. Please contact your administrator for access.'
  end

  def set_invitation
    return unless invitation_token.present?

    @invitation = FamilyInvitation.find_by(token: invitation_token)
  end

  def valid_invitation_token?
    return false unless invitation_token.present?

    invitation = FamilyInvitation.find_by(token: invitation_token)
    invitation&.can_be_accepted?
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
      flash[:alert] = "Account created successfully, but there was an issue accepting the invitation: #{service.error_message}"
    end
  rescue StandardError => e
    Rails.logger.error "Error accepting invitation during registration: #{e.message}"
    flash[:alert] = "Account created successfully, but there was an issue accepting the invitation. Please try accepting it again."
  end

  def sign_up_params
    super
  end
end
