# frozen_string_literal: true

class Family::InvitationPolicy < ApplicationPolicy
  def create?
    return false unless user

    user.family == record.family && user.family_owner?
  end

  def accept?
    return false unless user

    user.email == record.email
  end

  def destroy?
    create?
  end
end
