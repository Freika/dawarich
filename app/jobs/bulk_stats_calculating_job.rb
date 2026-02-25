# frozen_string_literal: true

class BulkStatsCalculatingJob < ApplicationJob
  queue_as :stats

  def perform
    user_ids = User.active.pluck(:id) + User.trial.pluck(:id)

    user_ids.each do |user_id|
      Stats::BulkCalculator.new(user_id).call
    end
  end
end
