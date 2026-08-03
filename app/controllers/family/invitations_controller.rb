# frozen_string_literal: true

class Family::InvitationsController < ApplicationController
  before_action :authenticate_user!, except: %i[show]
  # #index and #destroy stay open so a lapsed owner can still see and revoke
  # pending invitations; accepting them is blocked separately while lapsed.
  before_action :ensure_family_feature_available!, except: %i[show index destroy]
  before_action :set_family, except: %i[show]
  before_action :set_invitation_by_id_and_family, only: %i[destroy]

  def index
    authorize @family, :show?

    @pending_invitations = @family.family_invitations.active
  end

  def show
    token = params[:token] || params[:id]
    @invitation = Family::Invitation.find_by!(token: token)

    if @invitation.expired?
      redirect_to root_path,
                  alert: I18n.t('controllers.family.invitations.this_invitation_has_expired') and return
    end

    unless @invitation.pending?
      redirect_to root_path,
                  alert: I18n.t('controllers.family.invitations.this_invitation_is_no_longer_valid') and return
    end

    # Warns the invitee up front instead of letting them click Accept only to
    # be refused by the plan validation in Families::AcceptInvitation.
    @family_plan_active = DawarichSettings.family_feature_available_for?(@invitation.family.owner)
  end

  def create
    authorize @family, :invite?

    service = Families::Invite.new(
      family: @family,
      email: invitation_params[:email],
      invited_by: current_user
    )

    if service.call
      redirect_to family_path, notice: I18n.t('controllers.family.invitations.invitation_sent_successfully')
    else
      redirect_to family_path,
                  alert: service.error_message || I18n.t('controllers.family.invitations.failed_to_send_invitation')
    end
  end

  def destroy
    authorize @family, :manage_invitations?

    begin
      if @invitation.update(status: :cancelled)
        redirect_to family_home_path, notice: I18n.t('controllers.family.invitations.invitation_cancelled')
      else
        redirect_to family_home_path,
                    alert: I18n.t('controllers.family.invitations.failed_to_cancel_invitation_please_try_again')
      end
    rescue StandardError => e
      Rails.logger.error "Error cancelling family invitation: #{e.message}"
      alert = I18n.t('controllers.family.invitations.an_unexpected_error_occurred_while_cancelling_the_invitation')
      redirect_to family_home_path,
                  alert: alert
    end
  end

  private

  def set_family
    @family = current_user.family

    return if @family

    redirect_to new_family_path,
                alert: I18n.t('controllers.family.invitations.you_are_not_in_a_family') and return
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
