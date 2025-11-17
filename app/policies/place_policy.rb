# frozen_string_literal: true

class PlacePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end

  def index?
    true
  end

  def show?
    owner?
  end

  def create?
    true
  end

  def new?
    create?
  end

  def update?
    owner?
  end

  def edit?
    update?
  end

  def destroy?
    owner?
  end

  def nearby?
    true
  end

  private

  def owner?
    record.user_id == user.id
  end
end
