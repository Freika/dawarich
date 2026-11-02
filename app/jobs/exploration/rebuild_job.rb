# frozen_string_literal: true

class Exploration::RebuildJob < ApplicationJob
  queue_as :low_priority

  def perform(user_id)
    user = User.find_by(id: user_id)
    Exploration::Rebuild.new(user).call if user
  end
end
