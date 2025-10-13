# frozen_string_literal: true

class Family::InvitationPolicy < ApplicationPolicy
  def create?
    return false unless user

    user.family == record.family && user.family_owner?
  end

  def accept?
    # Users can accept invitations sent to their email
    return false unless user

    user.email == record.email
  end

  def destroy?
    # Only family owners can cancel invitations
    create?
  end
end
