# frozen_string_literal: true

class Family::MembershipPolicy < ApplicationPolicy
  def show?
    user.family == record.family
  end

  def update?
    # Users can update their own settings
    return true if user == record.user

    # Family owners can update any member's settings
    user.family == record.family && user.family_owner?
  end

  def destroy?
    # Users can remove themselves (handled by family leave logic)
    return true if user == record.user

    # Family owners can remove other members
    user.family == record.family && user.family_owner?
  end
end
