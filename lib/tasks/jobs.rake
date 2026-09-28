# frozen_string_literal: true

namespace :dawarich do
  namespace :jobs do
    owner_row_locked = lambda do |key|
      abort("#{key}: the owner row stayed locked by another transaction (for example a long user-data import) " \
            "for #{JobOwnership::LOCK_TIMEOUT}. Nothing changed; run the task again once that transaction ends.")
    end

    desc 'Route a job key back to Sidekiq and pin it so Phoenix does not claim it again'
    task :release, [:key] => :environment do |_task, args|
      key = args[:key].presence || abort('usage: bin/rails "dawarich:jobs:release[<key>]"')
      JobOwnership.release!(key, by: JobOwnership.operator).each { |moved| puts "#{moved}: sidekiq (pinned)" }
    rescue ActiveRecord::LockWaitTimeout
      owner_row_locked.call(key)
    end

    desc 'Let Phoenix claim a released job key again at its next boot'
    task :unpin, [:key] => :environment do |_task, args|
      key = args[:key].presence || abort('usage: bin/rails "dawarich:jobs:unpin[<key>]"')
      JobOwnership.unpin!(key, by: JobOwnership.operator).each { |unpinned| puts "#{unpinned}: claimable" }
    rescue ActiveRecord::LockWaitTimeout
      owner_row_locked.call(key)
    end

    desc 'Release a command key to Sidekiq (pinned) and hand its pending outbox commands to Sidekiq'
    task :rehome, [:key] => :environment do |_task, args|
      key = args[:key].to_s
      abort('usage: bin/rails "dawarich:jobs:rehome[command:<type>]"') unless key.start_with?('command:')

      type = key.delete_prefix('command:')
      result = JobCommands.rehome!(type, by: JobOwnership.operator)
      puts "#{key}: sidekiq (pinned), #{result[:moved]} command(s) re-homed to Sidekiq, " \
           "#{result[:left]} command(s) left in Phoenix"
      if result[:left].positive?
        puts 'Commands left in Phoenix will finish in Phoenix. Wait until dawarich:jobs:status shows ' \
             'no pending commands and no incomplete Oban jobs for this worker before rolling back.'
      end
      JobOutbox.pending.where(command_type: type).group(:command_version).count.each do |version, left|
        puts "#{left} rows with command_version #{version} left pending"
      end
      if result[:error]
        abort("Re-homing stopped: a Sidekiq enqueue raised #{result[:error]}. The commands not re-homed stay " \
              "pending and finish in Phoenix unless you run bin/rails \"dawarich:jobs:rehome[#{key}]\" again " \
              "once Sidekiq's Redis is reachable.")
      end
    rescue ActiveRecord::LockWaitTimeout
      owner_row_locked.call(key)
    end

    desc 'Send a quarantined outbox command through the relay again, keeping its event id'
    task :replay, %i[event_id reason] => :environment do |_task, args|
      if args[:event_id].blank? || args[:reason].blank?
        abort('usage: bin/rails "dawarich:jobs:replay[<event_id>,<reason>]"')
      end

      JobCommands.replay!(args[:event_id], actor: JobOwnership.operator, reason: args[:reason])
      puts "#{args[:event_id]}: pending"
    end

    desc 'Show who runs each job key, the outbox, Phoenix heartbeats and Oban job counts'
    task status: :environment do
      summary = JobHealth.compute(ENV.fetch('DAWARICH_PHOENIX_NODE', nil))
      puts JSON.pretty_generate(summary:, gauges: JobHealth.gauges)
    end
  end
end
