# frozen_string_literal: true

class Api::V1::Families::InvitationsController < Api::V1::Families::ManagementBaseController
  skip_before_action :reject_pending_payment!, only: %i[show accept]
  before_action :ensure_family_feature_available!, only: :create

  def index
    family = management_family
    authorize_management(family, :manage_invitations?)
    invitations = family.family_invitations.active.order(:created_at)
    render json: { invitations: invitations.map { |invitation| invitation_payload(invitation) } }
  end

  def show
    invitation = visible_invitation
    render json: { invitation: invitation_payload(invitation) }
  end

  def create
    family = management_family
    authorize_management(family, :invite?)
    email = params.expect(family_invitation: [:email])[:email].to_s
    service = Families::Invite.new(family: family, email: email, invited_by: current_api_user)
    return validation_failed(service.error_message) unless service.call

    render json: { invitation: invitation_payload(service.invitation) }, status: :created
  end

  def destroy
    family = management_family
    authorize_management(family, :manage_invitations?)
    invitation = family.family_invitations.find_by!(token: params[:token])
    family.with_lock do
      invitation.reload
      # Accepted/expired invitations are historical records, not revocable seats.
      return validation_failed('Only pending invitations can be revoked') unless invitation.pending?

      invitation.update!(status: :cancelled)
    end
    head :no_content
  end

  def accept
    invitation = visible_invitation
    authorize_management(invitation, :create?, policy_class: Family::MembershipPolicy)
    service = Families::AcceptInvitation.new(invitation: invitation, user: current_api_user)
    return validation_failed(service.error_message) unless service.call

    current_api_user.reload
    membership = current_api_user.family_membership
    render json: {
      family: { id: invitation.family_id, name: invitation.family.name },
      membership: { id: membership.id, user_id: membership.user_id, role: membership.role }
    }
  end

  private

  def visible_invitation
    invitation = Family::Invitation.includes(:family).find_by!(token: params[:token])
    return invitation if invitation.email == current_api_user.email
    return invitation if current_api_user.family == invitation.family && current_api_user.family_owner?

    raise ActiveRecord::RecordNotFound
  end
end
