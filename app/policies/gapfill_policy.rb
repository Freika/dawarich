# frozen_string_literal: true

class GapfillPolicy < ApplicationPolicy
  def preview?
    user.present?
  end

  def create?
    user.present?
  end
end
