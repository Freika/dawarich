# frozen_string_literal: true

class FamilyInvitationsController < ApplicationController
  before_action :authenticate_user!, except: %i[show accept]
  before_action :ensure_family_feature_enabled!, except: %i[show accept]
  before_action :set_family, except: %i[show accept]
  before_action :set_invitation_by_token, only: %i[show accept]
  before_action :set_invitation_by_id, only: %i[destroy]

  def index
    authorize @family, :show?

    @pending_invitations = @family.family_invitations.active
  end

  def show
    # Public endpoint for invitation acceptance
    if @invitation.expired?
      redirect_to root_path, alert: 'This invitation has expired.' and return
    end

    unless @invitation.pending?
      redirect_to root_path, alert: 'This invitation is no longer valid.' and return
    end

    # If user is not authenticated, redirect to registration with invitation token
    unless user_signed_in?
      redirect_to new_user_registration_path(invitation_token: @invitation.token) and return
    end

    # User is authenticated and invitation is valid - proceed with normal flow
  end

  def create
    authorize @family, :invite?

    service = Families::Invite.new(
      family: @family,
      email: invitation_params[:email],
      invited_by: current_user
    )

    if service.call
      redirect_to family_path(@family), notice: 'Invitation sent successfully!'
    else
      redirect_to family_path(@family), alert: service.error_message || 'Failed to send invitation'
    end
  end

  def accept
    authenticate_user!

    # Additional validations before attempting to accept
    unless @invitation.pending?
      redirect_to root_path, alert: 'This invitation has already been processed' and return
    end

    if @invitation.expired?
      redirect_to root_path, alert: 'This invitation has expired' and return
    end

    if @invitation.email != current_user.email
      redirect_to root_path, alert: 'This invitation is not for your email address' and return
    end

    service = Families::AcceptInvitation.new(
      invitation: @invitation,
      user: current_user
    )

    if service.call
      redirect_to family_path(current_user.reload.family),
                  notice: "Welcome to #{@invitation.family.name}! You're now part of the family."
    else
      redirect_to root_path, alert: service.error_message || 'Unable to accept invitation'
    end
  rescue StandardError => e
    Rails.logger.error "Error accepting family invitation: #{e.message}"
    redirect_to root_path, alert: 'An unexpected error occurred. Please try again later'
  end

  def destroy
    authorize @family, :manage_invitations?

    if @invitation.update(status: :cancelled)
      redirect_to family_path(@family),
                  notice: "Invitation to #{@invitation.email} has been cancelled"
    else
      redirect_to family_path(@family),
                  alert: 'Failed to cancel invitation. Please try again'
    end
  rescue StandardError => e
    Rails.logger.error "Error cancelling family invitation: #{e.message}"
    redirect_to family_path(@family),
                alert: 'An unexpected error occurred while cancelling the invitation'
  end

  private

  def ensure_family_feature_enabled!
    unless DawarichSettings.family_feature_enabled?
      redirect_to root_path, alert: 'Family feature is not available'
    end
  end

  def set_family
    @family = current_user.family

    redirect_to families_path, alert: 'Family not found' and return unless @family
  end

  def set_invitation_by_token
    @invitation = FamilyInvitation.find_by!(token: params[:id])
  end

  def set_invitation_by_id
    @invitation = @family.family_invitations.find(params[:id])
  end

  def invitation_params
    params.require(:family_invitation).permit(:email)
  end
end
