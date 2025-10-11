# frozen_string_literal: true

class Family::MembershipPolicy < ApplicationPolicy
  def show?
    return false unless user

    user.family == record.family
  end

  def update?
    return false unless user

    # Users can update their own settings
    return true if user == record.user

    # Family owners can update any member's settings
    show? && user.family_owner?
  end

  def destroy?
    return false unless user

    # Users can remove themselves (handled by family leave logic)
    return true if user == record.user

    # Family owners can remove other members
    update?
  end
end
