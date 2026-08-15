# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'dawarich places rake tasks' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == 'dawarich:cleanup_suggested_places' }
  end

  after do
    Rake::Task['dawarich:cleanup_suggested_places'].reenable
    Rake::Task['dawarich:backfill_place_names'].reenable
  end

  describe 'dawarich:cleanup_suggested_places' do
    it 'enqueues OrphanCleanupJob for each user plus an ownerless pass' do
      create(:user)
      create(:user)
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      expected_count = User.count + 1 # per-user jobs + one ownerless (nil) pass

      Rake::Task['dawarich:cleanup_suggested_places'].invoke

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count do |j|
        j[:job] == Places::OrphanCleanupJob
      end).to eq(expected_count)
    end

    it 'enqueues exactly one ownerless (nil) OrphanCleanupJob pass' do
      create(:user)
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      Rake::Task['dawarich:cleanup_suggested_places'].invoke

      ownerless_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |j|
        j[:job] == Places::OrphanCleanupJob && j[:args] == [nil]
      end
      expect(ownerless_jobs.size).to eq(1)
    end
  end

  describe 'dawarich:backfill_place_names' do
    it 'enqueues BulkNameFetchingJob once' do
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      Rake::Task['dawarich:backfill_place_names'].invoke

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j[:job] == Places::BulkNameFetchingJob }).to eq(1)
    end
  end
end
