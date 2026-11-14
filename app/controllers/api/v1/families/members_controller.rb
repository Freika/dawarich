# frozen_string_literal: true

class Api::V1::Families::MembersController < Api::V1::Families::ManagementBaseController
  def destroy
    membership = management_family.family_memberships.find(params[:id])
    remove_membership(membership)
  end

  def leave
    membership = current_api_user.family_membership || raise(ActiveRecord::RecordNotFound)
    remove_membership(membership)
  end

  private

  def remove_membership(membership)
    authorize_management(membership, :destroy?, policy_class: Family::MembershipPolicy)
    service = Families::Memberships::Destroy.new(user: current_api_user, member_to_remove: membership.user)
    return validation_failed(service.error_message) unless service.call

    head :no_content
  end
end
