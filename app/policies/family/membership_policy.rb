# frozen_string_literal: true

class Family::MembershipPolicy < ApplicationPolicy
  def create?
    return false unless user
    return false unless record.is_a?(Family::Invitation)

    record.email == user.email && record.pending? && !record.expired?
  end

  def destroy?
    return false unless user
    return true if user == record.user

    user.family == record.family && user.family_owner?
  end
end
