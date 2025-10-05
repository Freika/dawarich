# frozen_string_literal: true

class Family::InvitationsController < ApplicationController
  before_action :authenticate_user!, except: %i[show]
  before_action :ensure_family_feature_enabled!, except: %i[show]
  before_action :set_family, except: %i[show accept]
  before_action :set_invitation_by_id_and_family, only: %i[destroy]
  before_action :set_invitation_by_id, only: %i[accept]

  def index
    authorize @family, :show?

    @pending_invitations = @family.family_invitations.active
  end

  def show
    @invitation = FamilyInvitation.find_by!(token: params[:token])

    if @invitation.expired?
      redirect_to root_path, alert: 'This invitation has expired.' and return
    end

    unless @invitation.pending?
      redirect_to root_path, alert: 'This invitation is no longer valid.' and return
    end
  end

  def create
    authorize @family, :invite?

    service = Families::Invite.new(
      family: @family,
      email: invitation_params[:email],
      invited_by: current_user
    )

    if service.call
      redirect_to family_path, notice: 'Invitation sent successfully!'
    else
      redirect_to family_path, alert: service.error_message || 'Failed to send invitation'
    end
  end

  def accept
    unless @invitation.pending?
      redirect_to root_path, alert: 'This invitation has already been processed' and return
    end

    if @invitation.expired?
      redirect_to root_path, alert: 'This invitation is no longer valid or has expired' and return
    end

    if @invitation.email != current_user.email
      redirect_to root_path, alert: 'This invitation is not for your email address' and return
    end

    service = Families::AcceptInvitation.new(
      invitation: @invitation,
      user: current_user
    )

    if service.call
      redirect_to family_path, notice: 'Welcome to the family!'
    else
      redirect_to root_path, alert: service.error_message || 'Unable to accept invitation'
    end
  rescue StandardError => e
    Rails.logger.error "Error accepting family invitation: #{e.message}"
    redirect_to root_path, alert: 'An unexpected error occurred. Please try again later'
  end

  def destroy
    authorize @family, :manage_invitations?

    begin
      if @invitation.update(status: :cancelled)
        redirect_to family_path, notice: 'Invitation cancelled'
      else
        redirect_to family_path, alert: 'Failed to cancel invitation. Please try again'
      end
    rescue StandardError => e
      Rails.logger.error "Error cancelling family invitation: #{e.message}"
      redirect_to family_path, alert: 'An unexpected error occurred while cancelling the invitation'
    end
  end

  private

  def set_family
    @family = current_user.family

    redirect_to new_family_path, alert: 'You are not in a family' and return unless @family
  end

  def set_invitation_by_id
    @invitation = FamilyInvitation.find_by!(token: params[:id])
  end

  def set_invitation_by_id_and_family
    # For authenticated nested routes: /families/:family_id/invitations/:id
    # The :id param contains the token value
    @family = current_user.family
    @invitation = @family.family_invitations.find_by!(token: params[:id])
  end

  def invitation_params
    params.require(:family_invitation).permit(:email)
  end
end
