# frozen_string_literal: true

class FamilyPolicy < ApplicationPolicy
  def show?
    user.family == record
  end

  def create?
    return false if user.in_family?
    return true if DawarichSettings.self_hosted?

    # Add cloud subscription checks here when implemented
    # For now, allow all users to create families
    true
  end

  def update?
    user.family == record && user.family_owner?
  end

  def destroy?
    user.family == record && user.family_owner?
  end

  def leave?
    user.family == record && !family_owner_with_members?
  end

  def invite?
    user.family == record && user.family_owner?
  end

  def manage_invitations?
    user.family == record && user.family_owner?
  end

  private

  def family_owner_with_members?
    user.family_owner? && record.members.count > 1
  end
end
