# frozen_string_literal: true

namespace :dawarich do
  namespace :jobs do
    desc 'Route a job key back to Sidekiq and pin it so Phoenix does not claim it again'
    task :release, [:key] => :environment do |_task, args|
      key = args[:key].presence || abort('usage: bin/rails "dawarich:jobs:release[<key>]"')
      JobOwnership.release!(key, by: JobOwnership.operator)
      puts "#{key}: sidekiq (pinned)"
    end

    desc 'Let Phoenix claim a released job key again at its next boot'
    task :unpin, [:key] => :environment do |_task, args|
      key = args[:key].presence || abort('usage: bin/rails "dawarich:jobs:unpin[<key>]"')
      JobOwnership.unpin!(key, by: JobOwnership.operator)
      puts "#{key}: claimable"
    end

    desc 'Release a command key to Sidekiq (pinned) and hand its pending outbox commands to Sidekiq'
    task :rehome, [:key] => :environment do |_task, args|
      key = args[:key].to_s
      abort('usage: bin/rails "dawarich:jobs:rehome[command:<type>]"') unless key.start_with?('command:')

      type = key.delete_prefix('command:')
      count = JobCommands.rehome!(type, by: JobOwnership.operator)
      puts "#{key}: sidekiq (pinned), #{count} command(s) re-homed to Sidekiq"
      JobOutbox.pending.where(command_type: type).group(:command_version).count.each do |version, left|
        puts "#{left} rows with command_version #{version} left pending"
      end
    end

    desc 'Send a quarantined outbox command through the relay again, keeping its event id'
    task :replay, %i[event_id reason] => :environment do |_task, args|
      if args[:event_id].blank? || args[:reason].blank?
        abort('usage: bin/rails "dawarich:jobs:replay[<event_id>,<reason>]"')
      end

      JobCommands.replay!(args[:event_id], actor: JobOwnership.operator, reason: args[:reason])
      puts "#{args[:event_id]}: pending"
    end
  end
end
