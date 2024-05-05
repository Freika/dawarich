# frozen_string_literal: true

class StatCreatingJob < ApplicationJob
  queue_as :stats

  def perform(user_ids = nil)
    CreateStats.new(user_ids).call
  end
end
