# frozen_string_literal: true

class WebhookPolicy < ApplicationPolicy
  def index?
    allowed?
  end

  def create?
    allowed?
  end

  def new?
    create?
  end

  def show?
    owner? && allowed?
  end

  def update?
    show?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def test?
    update?
  end

  def regenerate_secret?
    update?
  end

  private

  def owner?
    record.is_a?(Webhook) && record.user_id == user.id
  end

  def allowed?
    user.entitlements.pro_api?
  end
end
