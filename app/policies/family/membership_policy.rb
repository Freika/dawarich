# frozen_string_literal: true

class Family::MembershipPolicy < ApplicationPolicy
  def create?
    return false unless user
    return false unless record.is_a?(Family::Invitation)

    # User can only accept invitations that:
    # 1. Are for their email address
    # 2. Are still pending
    # 3. Haven't expired
    record.email == user.email && record.pending? && !record.expired?
  end

  def destroy?
    return false unless user
    return true if user == record.user

    # Family owners can remove other members
    user.family == record.family && user.family_owner?
  end
end
