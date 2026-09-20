# frozen_string_literal: true

class Family::MembershipsController < ApplicationController
  before_action :authenticate_user!
  # #create is the invitation-accepting path: the invitee is not in a family yet
  # and does not hold the plan themselves, so the plan check would lock them out
  # of the family they were invited to. Family::MembershipPolicy authorizes it.
  # #destroy stays open so members can leave (and owners can remove members)
  # after the plan lapses.
  before_action :ensure_family_feature_available!, except: %i[create destroy]
  before_action :set_family, except: %i[create]
  before_action :set_membership, only: %i[destroy]
  before_action :set_invitation, only: %i[create]

  def create
    authorize @invitation, policy_class: Family::MembershipPolicy

    service = Families::AcceptInvitation.new(
      invitation: @invitation,
      user: current_user
    )

    if service.call
      redirect_to family_path, notice: I18n.t('controllers.family.memberships.welcome_to_the_family')
    else
      redirect_to root_path,
                  alert: service.error_message || I18n.t('controllers.family.memberships.unable_to_accept_invitation')
    end
  rescue Pundit::NotAuthorizedError
    alert = if @invitation.expired?
              I18n.t('controllers.family.memberships.invitation_expired')
            elsif !@invitation.pending?
              I18n.t('controllers.family.memberships.invitation_processed')
            elsif @invitation.email != current_user.email
              I18n.t('controllers.family.memberships.invitation_email_mismatch')
            else
              I18n.t('controllers.family.memberships.not_authorized_to_accept')
            end

    redirect_to root_path, alert: alert
  rescue StandardError => e
    Rails.logger.error "Error accepting family invitation: #{e.message}"

    redirect_to root_path,
                alert: I18n.t('controllers.family.memberships.an_unexpected_error_occurred_please_try_again_later')
  end

  def destroy
    authorize @membership

    member_user = @membership.user
    service = Families::Memberships::Destroy.new(user: current_user, member_to_remove: member_user)

    if service.call
      if member_user == current_user
        redirect_to new_family_path, notice: I18n.t('controllers.family.memberships.you_have_left_the_family')
      else
        redirect_to family_home_path,
                    notice: I18n.t('controllers.family.memberships.email_has_been_removed_from_the_family',
                                   email: member_user.email)
      end
    else
      redirect_to family_home_path,
                  alert: service.error_message || I18n.t('controllers.family.memberships.failed_to_remove_member')
    end
  end

  private

  def set_family
    @family = current_user.family

    return if @family

    redirect_to new_family_path,
                alert: I18n.t('controllers.family.memberships.you_are_not_in_a_family') and return
  end

  def set_membership
    @membership = @family.family_memberships.find(params[:id])
  end

  def set_invitation
    @invitation = Family::Invitation.find_by!(token: params[:token])
  end
end
