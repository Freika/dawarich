# frozen_string_literal: true

# This job is being run on daily basis at 00:05 to suggest visits for all users
# with the default timespan of 1 day.
class BulkVisitsSuggestingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  # Passing timespan of more than 3 years somehow results in duplicated Places
  def perform(marker = nil, start_at: 1.day.ago.beginning_of_day, end_at: 1.day.ago.end_of_day, user_ids: [],
              user_id: nil)
    raise ArgumentError, 'invalid cron marker' unless marker.nil? || marker == 'a12d3_cron'

    return unless Geocoding::Config.resolved_config.enabled?

    return if marker && JobOwnership.with_owner(Visits::BulkCommands::KEY) { :owned } == :not_owner

    user_ids = (Array(user_ids) | Array(user_id)).compact
    users = user_ids.any? ? User.active.where(id: user_ids) : User.active
    start_at = start_at.to_datetime
    end_at = end_at.to_datetime
    return if marker.nil? && Visits::BulkCommands.forward(start_at, end_at, user_ids, job_id)

    time_chunks = Visits::TimeChunks.new(start_at:, end_at:).call
    root = Visits::BulkCommands.root(job_id, marker && Integrations::SchedulingCommands.slot(self, nil))

    users.active.find_each do |user|
      next unless user.safe_settings.visits_suggestions_enabled?
      next unless user.points_count&.positive?

      work = -> { Visits::BulkCommands.schedule(user, time_chunks, root) }
      result = if marker
                 JobOwnership.with_owner(Visits::BulkCommands::KEY, &work)
               else
                 ActiveRecord::Base.transaction { work.call }
               end
      break if result == :not_owner
    end
  end
end
