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
  end
end
