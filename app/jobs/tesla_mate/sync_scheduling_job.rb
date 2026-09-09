# frozen_string_literal: true

module TeslaMate
  class SyncSchedulingJob < ApplicationJob
    queue_as :imports

    def perform
      User.where("settings->>'teslamate_url' <> ''")
          .find_each { |user| TeslaMate::SyncJob.perform_later(user.id) }
    end
  end
end
