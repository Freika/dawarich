# frozen_string_literal: true

class WebhookPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    user_owns_record? && pro_or_self_hosted?
  end

  def create?
    pro_or_self_hosted?
  end

  def new?
    create?
  end

  def update?
    user_owns_record? && pro_or_self_hosted?
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

  private

  def user_owns_record?
    record.user_id == user.id
  end

  def pro_or_self_hosted?
    DawarichSettings.self_hosted? || user.pro?
  end
end
