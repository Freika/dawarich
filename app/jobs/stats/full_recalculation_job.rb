# frozen_string_literal: true

module Stats
  class FullRecalculationJob < ApplicationJob
    queue_as :stats

    def perform(user_id)
      Stats::RecalculationDebouncer.new(user_id).clear

      user = User.find_by(id: user_id)
      return if user.nil?

      Stats::EnqueueFullRecalculation.new(user).call
    end
  end
end
