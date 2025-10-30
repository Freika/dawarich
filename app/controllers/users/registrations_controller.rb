# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  before_action :set_invitation, only: %i[new create]
  before_action :check_registration_allowed, only: %i[new create]
  before_action :store_utm_params, only: %i[new]

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
    return if valid_invitation_token?

    redirect_to root_path,
                alert: 'Registration is not available. Please contact your administrator for access.'
  end

  def set_invitation
    return unless invitation_token.present?

    @invitation = Family::Invitation.find_by(token: invitation_token)
  end

  def self_hosted_mode?
    env_value = ENV['SELF_HOSTED']
    return ActiveModel::Type::Boolean.new.cast(env_value) unless env_value.nil?

    false
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
      flash[:alert] = "Account created successfully, but there was an issue accepting the invitation: #{service.error_message}"
    end
  rescue StandardError => e
    Rails.logger.error "Error accepting invitation during registration: #{e.message}"
    flash[:alert] = "Account created successfully, but there was an issue accepting the invitation. Please try accepting it again."
  end

  def sign_up_params
    super
  end

  def store_utm_params
    utm_params = %w[utm_source utm_medium utm_campaign utm_term utm_content]
    utm_params.each do |param|
      session[param] = params[param] if params[param].present?
    end
  end

  def assign_utm_params(user)
    utm_params = %w[utm_source utm_medium utm_campaign utm_term utm_content]
    utm_data = {}

    utm_params.each do |param|
      utm_data[param] = session[param] if session[param].present?
      session.delete(param) # Clean up session after assignment
    end

    user.update_columns(utm_data) if utm_data.any?
  end
end
