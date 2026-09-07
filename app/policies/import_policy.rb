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

  def download?
    show?
  end

  # Users can create new imports only while their subscription window is open.
  # This intentionally mirrors `ApplicationController#authenticate_active_user!`
  # (the controller filter that gates `ImportsController#create`) so the `new`
  # and `create` gates cannot diverge for a trial user whose `active_until` has
  # passed.
  def new?
    create?
  end

  def create?
    user.present? && user.active_until&.future?
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
      return scope.none if user.blank?

      # Users can only see their own imports
      scope.where(user: user)
    end
  end
end
