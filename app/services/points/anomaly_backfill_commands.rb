# frozen_string_literal: true

module Points
  module AnomalyBackfillCommands
    COMMANDS = {
      'points.anomaly_backfill' => {
        version: 1,
        sidekiq: ->(payload, at) { JobCommands.enqueue_after_commit(nil) { enqueue(payload, at) } }
      }
    }.freeze

    HANDLERS = {
      'points.anomaly_backfill' => {
        guard: 'The source backfill resumes monthly cursors under the shared user lease',
        call: lambda { |payload|
          JobCommands.produce('points.anomaly_backfill', payload.except('run_at'),
                              aggregate_id: payload.fetch('user_id'), producer: name,
                              scheduled_at: Time.zone.at(payload.fetch('run_at')))
        }
      }
    }.freeze

    module_function

    def forward(job, user_id, reset:, notify:, rebuild:)
      return false unless job.executions.positive? && JobOwnership.oban?('command:points.anomaly_backfill')

      payload = { 'user_id' => user_id, 'reset' => !reset.nil? && reset != false,
                  'notify' => !notify.nil? && notify != false, 'rebuild' => rebuild.to_s,
                  'source_job_id' => job.job_id, 'ambient_zone' => Time.zone.name,
                  'progress' => job.serialize.fetch('continuation') }
      JobCommands.forward('points.anomaly_backfill', payload, event_id: job.job_id, aggregate_id: user_id,
                           producer: job.class.name, scheduled_at: job.scheduled_at || Time.current)
      true
    end

    def enqueue(payload, at)
      Time.use_zone(payload.fetch('ambient_zone')) do
        job = Points::AnomalyBackfillUserJob.new(payload.fetch('user_id'), reset: payload.fetch('reset'),
                                                notify: payload.fetch('notify'),
                                                rebuild: payload.fetch('rebuild').to_sym)
        job.job_id = payload.fetch('source_job_id')
        job = ActiveJob::Base.deserialize(job.serialize.merge('continuation' => payload.fetch('progress')))
        job.enqueue(wait_until: at)
      end
    end
  end
end
