# frozen_string_literal: true

module Cache
  module Commands
    COMMANDS = {
      'cache.preheat_user' => {
        version: 1,
        sidekiq: ->(payload, at) { JobCommands.enqueue_after_commit(nil) { preheat_user(payload, at) } }
      }
    }.freeze

    HANDLERS = {
      'cache.preheat_user' => {
        guard: 'Source warming precedes current-owner durable dispatch and preserves the original job UUID',
        call: ->(payload) { preheat_user(payload, Time.zone.at(payload.fetch('run_at'))) }
      },
      'cache.preheat_sweep' => {
        guard: 'The retained source sweep repeats global warming and convergent per-user warming fanout',
        call: ->(payload) { preheat_sweep(payload, Time.zone.at(payload.fetch('run_at'))) }
      }
    }.freeze

    module_function

    def preheat_user(payload, at)
      Time.use_zone(payload.fetch('time_zone')) do
        job = Cache::UserPreheatingJob.new(payload.fetch('user_id'))
        job.job_id = payload.fetch('source_job_id')
        job.enqueue(wait_until: at)
      end
    end

    def preheat_sweep(payload, at)
      Time.use_zone(payload.fetch('time_zone')) do
        job = Cache::PreheatingJob.new
        job.job_id = payload.fetch('source_job_id')
        job.enqueue(wait_until: at)
      end
    end
  end
end
