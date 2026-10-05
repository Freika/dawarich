# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cache::PreheatingJob do
  include ActiveSupport::Testing::TimeHelpers
  before { Rails.cache.clear }

  it 'both cron owners retain the one-day global write and original warming fanout' do
    phoenix_tables!
    connection = ActiveRecord::Base.connection
    sequence = connection.select_one('SELECT last_value, is_called FROM phoenix.rails_commands_id_seq')
    travel_to(Time.utc(2026, 10, 3, 12)) do
      User.insert_all!([{ id: 180_121, email: 'cache-sweep@example.invalid', encrypted_password: '', status: 1,
                         plan: 1, settings: {}, created_at: Time.current, updated_at: Time.current }])
      writes = []
      listener = ->(*, payload) { writes << payload.slice(:key, :expires_in) }
      %i[sidekiq oban].each do |owner|
        job_owner!('cron:cache_preheating_job', owner)
        clear_enqueued_jobs
        writes.clear
        ActiveSupport::Notifications.subscribed(listener, 'cache_write.active_support') { described_class.new.perform }
        expect(writes).to eq([{ key: 'dawarich/countries_codes', expires_in: 86_400 }])
        expect(enqueued_jobs.sole.fetch('arguments')).to eq([180_121])
      end

      source = SecureRandom.uuid
      due = Time.current + 3600
      payload = { 'time_zone' => 'Asia/Tokyo', 'source_job_id' => source, 'run_at' => due.to_i }
      insert = ['INSERT INTO phoenix.rails_commands(kind,payload) VALUES (?,?::jsonb)',
                'cache.preheat_sweep', payload.to_json]
      sql = ActiveRecord::Base.sanitize_sql_array(insert)
      connection.execute(sql)
      JobOwnership.release!('cron:cache_preheating_job', by: 'spec')
      clear_enqueued_jobs
      expect(RailsCommands::Poller.drain_once).to eq(1)
      request = enqueued_jobs.sole.deep_dup
      expect(request.fetch('job_id')).to eq(source)
      expect(request.fetch('timezone')).to eq('Asia/Tokyo')
      expect(Time.iso8601(request.fetch('scheduled_at'))).to eq(due)
      clear_enqueued_jobs
      writes.clear
      ActiveSupport::Notifications.subscribed(listener, 'cache_write.active_support') do
        ActiveJob::Base.deserialize(request).perform_now
      end
      expect(writes).to eq([{ key: 'dawarich/countries_codes', expires_in: 86_400 }])
      expect(enqueued_jobs.sole.fetch('arguments')).to eq([180_121])
    end
  ensure
    if sequence
      connection.execute("SELECT setval('phoenix.rails_commands_id_seq', #{sequence.fetch('last_value')}, " \
                         "#{connection.quote(sequence.fetch('is_called'))})")
    end
  end

  it 'delegated source sweep keeps 500-user batches exact eligibility and one global warm' do
    phoenix_tables!
    users = (0..503).map do |index|
      { id: 180_201 + index * 2, email: "sweep-#{index}@example.invalid", encrypted_password: '',
        status: index % 4, settings: {}, plan: 1, deleted_at: index == 503 ? Time.current : nil,
        created_at: Time.current, updated_at: Time.current }
    end
    User.unscoped.insert_all!(users)
    batches = []
    allow(ActiveJob).to receive(:perform_all_later).and_wrap_original do |original, jobs|
      batches << jobs.map { |job| job.arguments.first }
      original.call(jobs)
    end
    writes = []
    listener = ->(*, payload) { writes << payload.slice(:key, :expires_in) }

    [false, true].product(%i[sidekiq oban]).each do |self_hosted, owner|
      job_owner!('cron:cache_preheating_job', owner)
      allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
      batches.clear
      writes.clear
      clear_enqueued_jobs
      ActiveSupport::Notifications.subscribed(listener, 'cache_write.active_support') { described_class.new.perform }
      expected = users.reject { |user| user[:deleted_at] || (!self_hosted && ![1, 2].include?(user[:status])) }
                      .map { |user| user[:id] }
      expect(batches.flatten).to eq(expected)
      expect(batches.map(&:length)).to eq(self_hosted ? [500, 3] : [252])
      expect(writes).to eq([{ key: 'dawarich/countries_codes', expires_in: 86_400 }])
    end
  end

  describe '#perform' do
    # skip_auto_trial pins the factory status: the after_commit :activate /
    # :start_trial hooks would otherwise rewrite it based on self_hosted?,
    # which these examples stub per context.
    let!(:active_user) { create(:user, skip_auto_trial: true) }
    let!(:trial_user) { create(:user, :trial, skip_auto_trial: true) }
    let!(:inactive_user) { create(:user, :inactive, skip_auto_trial: true) }
    let!(:pending_payment_user) { create(:user, status: :pending_payment, skip_auto_trial: true) }

    it 'runs on the cache queue' do
      expect(described_class.new.queue_name).to eq('cache')
    end

    it 'preheats the global country borders cache' do
      described_class.new.perform

      expect(Rails.cache.exist?('dawarich/countries_codes')).to be true
    end

    it 'does not write per-user caches itself' do
      described_class.new.perform

      expect(Rails.cache.exist?("dawarich/user_#{active_user.id}_years_tracked")).to be false
    end

    context 'on Dawarich Cloud' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'fans out to active users' do
        described_class.new.perform

        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(active_user.id)
      end

      it 'fans out to trial users' do
        described_class.new.perform

        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(trial_user.id)
      end

      it 'skips inactive users' do
        described_class.new.perform

        expect(Cache::UserPreheatingJob).not_to have_been_enqueued.with(inactive_user.id)
      end

      it 'skips users pending payment' do
        described_class.new.perform

        expect(Cache::UserPreheatingJob).not_to have_been_enqueued.with(pending_payment_user.id)
      end

      it 'enqueues exactly one job per active or trial user' do
        described_class.new.perform

        preheated = enqueued_jobs.filter_map do |job|
          job[:args].first if job[:job] == Cache::UserPreheatingJob
        end

        expect(preheated.count(active_user.id)).to eq(1)
        expect(preheated.count(trial_user.id)).to eq(1)
        expect(preheated).not_to include(inactive_user.id, pending_payment_user.id)
      end

      it 'preheats the fanned-out users once their jobs run' do
        perform_enqueued_jobs { described_class.new.perform }

        expect(Rails.cache.exist?("dawarich/user_#{active_user.id}_years_tracked")).to be true
        expect(Rails.cache.exist?("dawarich/user_#{trial_user.id}_years_tracked")).to be true
        expect(Rails.cache.exist?("dawarich/user_#{inactive_user.id}_years_tracked")).to be false
      end
    end

    context 'when self-hosted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'fans out to every user regardless of status' do
        described_class.new.perform

        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(active_user.id)
        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(trial_user.id)
        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(inactive_user.id)
        expect(Cache::UserPreheatingJob).to have_been_enqueued.with(pending_payment_user.id)
      end

      it 'enqueues exactly one job per user' do
        expect { described_class.new.perform }
          .to have_enqueued_job(Cache::UserPreheatingJob).exactly(User.count).times
      end
    end
  end
end
