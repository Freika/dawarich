# frozen_string_literal: true

module Stats
  class FullRecalculationJob < ApplicationJob
    queue_as :stats

    def perform(user_id)
      if executions.positive? && JobOwnership.oban?('command:stats.full_recalculation')
        return JobCommands.forward('stats.full_recalculation',
                                   { 'user_id' => user_id, 'source_job_id' => job_id },
                                   event_id: job_id, aggregate_id: user_id, producer: self.class.name,
                                   scheduled_at: scheduled_at || Time.current)
      end

      Stats::RecalculationDebouncer.new(user_id).clear

      user = User.find_by(id: user_id)
      return if user.nil?

      Stats::EnqueueFullRecalculation.new(user).call
    end
  end
end
