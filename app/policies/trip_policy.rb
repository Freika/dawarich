# frozen_string_literal: true

class TripPolicy < ApplicationPolicy
  def show?
    # Allow public access if trip is publicly accessible, otherwise require ownership
    record.public_accessible? || owner?
  end

  def create?
    true
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  def update_sharing?
    owner?
  end

  class Scope < Scope
    def resolve
      scope.where(user: user)
    end
  end

  private

  def owner?
    user && record.user_id == user.id
  end
end
