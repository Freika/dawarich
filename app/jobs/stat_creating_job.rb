# frozen_string_literal: true

class StatCreatingJob < ApplicationJob
  queue_as :stats

  def perform(user_ids = nil)
    user_ids = user_ids.nil? ? User.pluck(:id) : Array(user_ids)

    CreateStats.new(user_ids).call
  end
end
