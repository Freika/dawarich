# frozen_string_literal: true

class FamilyInvitationsController < ApplicationController
  before_action :authenticate_user!, except: %i[show accept]
  before_action :set_family, except: %i[show accept]
  before_action :set_invitation, only: %i[show accept destroy]

  def index
    authorize @family, :show?

    @pending_invitations = @family.family_invitations.active
  end

  def show
    # Public endpoint for invitation acceptance
    if @invitation.expired?
      redirect_to root_path, alert: 'This invitation has expired.'
      return
    end

    return if @invitation.pending?

    redirect_to root_path, alert: 'This invitation is no longer valid.'
    nil
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

    service = Families::AcceptInvitation.new(
      invitation: @invitation,
      user: current_user
    )

    if service.call
      redirect_to family_path(current_user.reload.family), notice: 'Welcome to the family!'
    else
      redirect_to root_path, alert: service.error_message || 'Unable to accept invitation'
    end
  end

  def destroy
    authorize @family, :manage_invitations?

    @invitation.update!(status: :cancelled)
    redirect_to family_path(@family), notice: 'Invitation cancelled'
  end

  private

  def set_family
    @family = current_user.family

    redirect_to families_path, alert: 'Family not found' and return unless @family
  end

  def set_invitation
    @invitation = FamilyInvitation.find_by!(token: params[:id])
  end

  def invitation_params
    params.require(:family_invitation).permit(:email)
  end
end
