# frozen_string_literal: true

class InsightsPolicy < ApplicationPolicy
  def index?
    user.present?
  end
end
