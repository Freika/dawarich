# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::Commands do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user) }
  let(:at) { Time.zone.parse('2026-03-29 12:34:56 UTC') }
  let(:month) { { 'user_id' => user.id, 'year' => 2024, 'month' => 3, 'notify_on_failure' => false } }

  def handle(kind, payload) = described_class::HANDLERS.fetch(kind).fetch(:call).call(payload)

  it 'native invalidation still evicts the shared Rails yearly snapshots consumed by both readers' do
    other = create(:user)
    keys = ["insights/yearly_digest/#{user.id}/2024/1700000000",
            "insights/yearly_digest/#{user.id}/2024/1700000001",
            "insights/yearly_digest/#{user.id}/2025/1700000000",
            "insights/yearly_digest/#{other.id}/2024/1700000000"]
    keys.each { |key| Rails.cache.write(key, 'snapshot', expires_in: 1.hour, version: 'source-v1') }
    total = "dawarich/user_#{user.id}_total_distance"
    Rails.cache.write(total, 99, expires_in: 1.day)
    expect(Rails.cache.read(keys.last, version: 'other')).to be_nil
    Rails.cache.redis.with do |redis|
      expect(redis.ttl(keys.last)).to be_between(3590, 3600)
      expect(redis.ttl(total)).to be_between(86_390, 86_400)
    end

    handler = RailsCommands::Registry::HANDLERS.fetch('stats.caches_invalidated').fetch(:call)
    handler.call('user_id' => user.id, 'year' => 2024, 'scope' => 'toponyms')
    expect(keys.first(2).map { |key| Rails.cache.read(key, version: 'source-v1') }).to eq([nil, nil])
    expect(keys.last(2).map { |key| Rails.cache.read(key, version: 'source-v1') }).to eq(%w[snapshot snapshot])
    expect(Rails.cache.read(total)).to eq(99)

    handler.call('user_id' => user.id, 'year' => nil, 'scope' => 'all')
    expect(Rails.cache.read(keys[2], version: 'source-v1')).to be_nil
    expect(Rails.cache.read(total)).to be_nil
    expect(Rails.cache.read(keys.last, version: 'source-v1')).to eq('snapshot')
    Rails.cache.redis.with { |redis| expect(redis.ttl(keys.last)).to be_between(3590, 3600) }
  end

  it 'stats.calculate_month enqueues the month at run_at with its notification flag' do
    expect { handle('stats.calculate_month', month.merge('run_at' => at.to_i)) }
      .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2024, 3, notify_on_failure: false).at(at)
  end

  it 'stats.calculate_month does nothing for a missing user' do
    expect { handle('stats.calculate_month', month.merge('user_id' => 0, 'run_at' => at.to_i)) }
      .not_to have_enqueued_job(Stats::CalculatingJob)
  end

  it 'stats.caches_invalidated deletes the toponym caches, or every user cache for scope all' do
    country = "dawarich/user_#{user.id}_countries_visited"
    distance = "dawarich/user_#{user.id}_total_distance"
    Rails.cache.write(country, 'countries')
    Rails.cache.write(distance, 99)
    handle('stats.caches_invalidated', { 'user_id' => user.id, 'year' => 2024, 'scope' => 'toponyms' })
    expect(Rails.cache.read(country)).to be_nil
    expect(Rails.cache.read(distance)).to eq(99)

    handle('stats.caches_invalidated', { 'user_id' => user.id, 'year' => 2024, 'scope' => 'all' })
    expect(Rails.cache.read(distance)).to be_nil
  end

  context 'full recalculation routing' do
    self.use_transactional_tests = false

    around do |example|
      connection = ActiveRecord::Base.connection
      sequence = connection.select_one('SELECT last_value, is_called FROM users_id_seq')
      example.run
    ensure
      connection.execute("SELECT setval('users_id_seq', #{sequence.fetch('last_value')}, " \
                         "#{connection.quote(sequence.fetch('is_called'))})")
    end

    before do
      phoenix_tables!
      phoenix_state!
      @full_user = create(:user)
      @full_key = "stats_full_recalculation:user:#{@full_user.id}"
      job_owner!('command:stats.full_recalculation', :sidekiq)
      clear_enqueued_jobs
    end

    after do
      JobOutbox.where(command_type: 'stats.full_recalculation', aggregate_id: @full_user.id).delete_all
      connection = ActiveRecord::Base.connection
      connection.execute("DELETE FROM phoenix.once_claims WHERE key=#{connection.quote(@full_key)}")
      connection.execute("DELETE FROM phoenix.job_owners WHERE key='command:stats.full_recalculation'")
      User.unscoped.where(id: @full_user.id).delete_all
      clear_enqueued_jobs
    end

    it 'forwards full stats by stable job id and retains the shared debounce delay' do
      travel_to Time.utc(2026, 10, 3, 12) do
        debouncer = Stats::RecalculationDebouncer.new(@full_user.id)
        debouncer.trigger
        queued = enqueued_jobs.sole.deep_dup
        source_id = queued.fetch('job_id')
        due = Time.current + 60
        expect(Time.iso8601(queued.fetch('scheduled_at'))).to eq(due)
        expect(queued.fetch('arguments')).to eq([@full_user.id])
        expire_claim_in(@full_key, '10 seconds')
        debouncer.trigger
        expect(enqueued_jobs.size).to eq(1)
        expect(claim_seconds(@full_key)).to be_between(299, 300)
        clear_enqueued_jobs
        job_owner!('command:stats.full_recalculation', :oban)
        job = ActiveJob::Base.deserialize(queued)
        job.perform_now
        job.perform_now
        row = JobOutbox.where(command_type: 'stats.full_recalculation', aggregate_id: @full_user.id).sole
        payload = { 'user_id' => @full_user.id, 'source_job_id' => source_id }
        expect(row).to have_attributes(event_id: source_id, payload:, command_version: 1, scheduled_at: due)
        expect(claim_seconds(@full_key)).to be_between(299, 300)
        expect(enqueued_jobs).to be_empty
        expect(JobCommands.rehome!('stats.full_recalculation', by: 'spec')).to eq(moved: 1, left: 0)
        rehomed = enqueued_jobs.sole
        expect(rehomed.fetch('job_id')).to eq(source_id)
        expect(rehomed.fetch('arguments')).to eq([@full_user.id])
        expect(Time.iso8601(rehomed.fetch('scheduled_at'))).to eq(due)
        expect(JobOutbox.exists?(source_id)).to be(false)
        clear_enqueued_jobs
        handle('stats.full_recalculation', payload.merge('run_at' => due.to_i))
        expect(enqueued_jobs.sole.fetch('job_id')).to eq(source_id)
        expect(Time.iso8601(enqueued_jobs.sole.fetch('scheduled_at'))).to eq(due)
      end
    end

    it 'failed full-stats rehome push retains its pending row' do
      job_owner!('command:stats.full_recalculation', :oban)
      source_id = SecureRandom.uuid
      payload = { 'user_id' => @full_user.id, 'source_job_id' => source_id }
      due = Time.current.change(usec: 0) + 60
      JobCommands.forward('stats.full_recalculation', payload, event_id: source_id,
                          aggregate_id: @full_user.id, producer: 'spec', scheduled_at: due)
      allow(Stats::FullRecalculationJob.queue_adapter)
        .to receive(:enqueue_at).and_raise(IOError, 'synthetic push failure')
      expect(JobCommands.rehome!('stats.full_recalculation', by: 'spec'))
        .to eq(moved: 0, left: 1, error: 'IOError')
      expect(JobOutbox.find(source_id)).to have_attributes(state: 'pending', payload:, scheduled_at: due)
      expect(JobOwnership.lock_owner('command:stats.full_recalculation')).to eq(:sidekiq)
      expect(enqueued_jobs).to be_empty
    end
  end
end
