# frozen_string_literal: true

class Family::InvitationPolicy < ApplicationPolicy
  def show?
    # Public endpoint for invitation acceptance - no authentication required
    true
  end

  def create?
    user.family == record.family && user.family_owner?
  end

  def accept?
    # Users can accept invitations sent to their email
    user.email == record.email
  end

  def destroy?
    # Only family owners can cancel invitations
    user.family == record.family && user.family_owner?
  end
end
