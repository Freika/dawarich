# frozen_string_literal: true

class BulkStatsCalculatingJob < ApplicationJob
  queue_as :stats

  def perform
    user_ids = User.pluck(:id)

    user_ids.each do |user_id|
      Stats::CalculatingJob.perform_later(user_id)
    end
  end
end
