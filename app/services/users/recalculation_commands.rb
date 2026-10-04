# frozen_string_literal: true

module Users
  module RecalculationCommands
    COMMANDS = {
      'users.recalculate_data' => {
        version: 1,
        sidekiq: ->(payload, at) { JobCommands.enqueue_after_commit(nil) { enqueue(payload, at) } }
      }
    }.freeze

    HANDLERS = {
      'users.recalculate_data' => {
        guard: 'The source rebuild recomputes each period and retains stable per-year track identities',
        call: lambda { |payload|
          JobCommands.produce('users.recalculate_data', payload.except('run_at'),
                              aggregate_id: payload.fetch('user_id'), producer: name,
                              scheduled_at: Time.zone.at(payload.fetch('run_at')))
        }
      }
    }.freeze

    module_function

    def normalize(payload)
      notify = payload.fetch('notify')
      payload.merge('year' => payload.fetch('year')&.to_i, 'notify' => !notify.nil? && notify != false)
    end

    def enqueue(payload, at)
      Time.use_zone(payload.fetch('ambient_zone')) do
        job = Users::RecalculateDataJob.new(payload.fetch('user_id'), year: payload.fetch('year'),
                                           notify: payload.fetch('notify'), job_queue: payload.fetch('job_queue'))
        job.job_id = payload.fetch('source_job_id')
        job.enqueue(wait_until: at)
      end
    end
  end
end
