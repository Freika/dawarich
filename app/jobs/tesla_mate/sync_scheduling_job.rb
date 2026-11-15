# frozen_string_literal: true

module TeslaMate
  class SyncSchedulingJob < ApplicationJob
    queue_as :imports

    def perform
      user_ids = User.where("settings->>'teslamate_url' <> ''").ids
      ActiveJob.perform_all_later(user_ids.map { |user_id| TeslaMate::SyncJob.new(user_id) })
    end
  end
end
