# frozen_string_literal: true

class ImportPolicy < ApplicationPolicy
  # Allow users to view the imports index
  def index?
    user.present?
  end

  # Users can only show their own imports
  def show?
    user.present? && record.user == user
  end

  # Users can create new imports if they are active or trial
  def new?
    create?
  end

  def create?
    user.present? && (user.active? || user.trial?)
  end

  # Users can only edit their own imports
  def edit?
    update?
  end

  def update?
    user.present? && record.user == user
  end

  # Users can only destroy their own imports
  def destroy?
    user.present? && record.user == user
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?

      # Users can only see their own imports
      scope.where(user: user)
    end
  end
end
