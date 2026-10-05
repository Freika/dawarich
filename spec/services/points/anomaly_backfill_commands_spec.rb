# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Recalculation command shims' do
  self.use_transactional_tests = false

  let(:due) { 1.hour.from_now.change(usec: 0) }
  let(:progress) { { 'completed' => ['reset_flags'], 'current' => ['filter_months', 1_735_689_600] } }
  let(:cases) do
    common = { 'source_job_id' => SecureRandom.uuid, 'ambient_zone' => 'Asia/Tokyo' }
    [
      ['stats.full_recalculation', Stats::FullRecalculationJob, [987_654], {}, common.except('ambient_zone')],
      ['users.recalculate_data', Users::RecalculateDataJob, [987_654],
       { year: 2025, notify: false, job_queue: 'low_priority' }, common],
      ['points.anomaly_backfill', Points::AnomalyBackfillUserJob, [987_654],
       { reset: true, notify: false, rebuild: :inline }, common.merge('progress' => progress)],
      ['release.anomalies', DataMigrations::RecalculateAnomaliesJob, [], { limit: 3 }, common],
      ['release.anomalies_user', DataMigrations::RecalculateAnomaliesUserJob, [987_654], { attempt: 4 }, common],
      ['release.per_tracker', DataMigrations::RecalculatePerTrackerTracksJob, [nil], {}, common]
    ].map do |type, klass, args, kwargs, payload|
      payload = payload.merge(kwargs.stringify_keys)
      payload['rebuild'] = payload['rebuild'].to_s if payload.key?('rebuild')
      payload['user_id'] = args.first unless type == 'release.anomalies'
      [type, klass, args, kwargs, payload.merge('source_job_id' => SecureRandom.uuid)]
    end
  end

  before do
    phoenix_tables!
    @event_ids = cases.map { _1.last.fetch('source_job_id') }
    cases.map(&:first).each { |type| job_owner!("command:#{type}", :sidekiq) }
    clear_enqueued_jobs
  end

  after do
    cases.map(&:first).each do |type|
      connection = ActiveRecord::Base.connection
      connection.execute("DELETE FROM phoenix.job_owners WHERE key=#{connection.quote("command:#{type}")}")
    end
    JobOutbox.where(event_id: @event_ids).delete_all
    clear_enqueued_jobs
  end

  def serialized(klass, args, kwargs, payload)
    job = Time.use_zone('Asia/Tokyo') { klass.new(*args, **kwargs) }
    job.job_id = payload.fetch('source_job_id')
    job.scheduled_at = due
    data = job.serialize
    data['continuation'] = progress if klass == Points::AnomalyBackfillUserJob
    data
  end

  it 'serialized legacy jobs forward stable ids and complete old fallback bodies' do
    allow(User).to receive(:find).and_call_original
    allow(User).to receive(:find_by).and_call_original
    cases.each do |type, klass, args, kwargs, payload|
      job_owner!("command:#{type}", :oban)
      data = serialized(klass, args, kwargs, payload)
      ActiveJob::Base.deserialize(data).perform_now
      row = JobOutbox.where(command_type: type).sole
      expect(row).to have_attributes(event_id: payload.fetch('source_job_id'), payload:, scheduled_at: due)
      ActiveJob::Base.deserialize(data).perform_now
      expect(JobOutbox.where(command_type: type).count).to eq(1)
      expect(enqueued_jobs).to be_empty
    end

    expect(User).not_to have_received(:find)
    expect(User).not_to have_received(:find_by)

    allow(User).to receive(:find).and_raise(ActiveRecord::RecordNotFound, 'inline missing')
    expect { Points::AnomalyBackfillUserJob.new.perform(987_654) }
      .to raise_error(ActiveRecord::RecordNotFound, 'inline missing')
    inline = Users::RecalculateDataJob.new
    allow(inline).to receive(:find_user_or_skip).and_raise(Tracks::PerUserLock::AcquisitionTimeout, 'inline busy')
    expect { inline.perform(987_654, notify: false) }
      .to raise_error(Tracks::PerUserLock::AcquisitionTimeout, 'inline busy')

    cases.map(&:first).each { |type| job_owner!("command:#{type}", :sidekiq) }
    allow(User).to receive(:find_by).and_return(nil)
    expect(Stats::RecalculationDebouncer).to receive(:new).with(987_654).and_call_original
    Stats::FullRecalculationJob.new.perform(987_654)
    expect { Users::RecalculateDataJob.new.perform(987_654, notify: false) }.not_to raise_error
    expect { DataMigrations::RecalculatePerTrackerTracksJob.new.perform(987_654) }.not_to raise_error
    dispatcher = DataMigrations::RecalculateAnomaliesJob.new
    expect(dispatcher).to receive(:next_users).with(3).and_return([[], []])
    dispatcher.perform(limit: 3)
    migration = DataMigrations::RecalculateAnomaliesUserJob.new
    expect(migration).to receive(:release_slot)
    migration.perform(987_654, attempt: 4)
  end

  it 'each pending command rehomes inline and failed pushes keep unpushed rows' do
    cases.each do |type, klass, args, kwargs, payload|
      clear_enqueued_jobs
      job_owner!("command:#{type}", :oban)
      reverse = RailsCommands::Registry.handler(type)
      expect(reverse).not_to be_nil
      reverse.call(payload.merge('run_at' => due.to_i))
      expect(JobOutbox.where(command_type: type).sole)
        .to have_attributes(event_id: payload.fetch('source_job_id'), payload:)
      second = payload.merge('source_job_id' => SecureRandom.uuid)
      @event_ids << second.fetch('source_job_id')
      reverse.call(second.merge('run_at' => due.to_i))
      pushes = 0
      allow(ApplicationJob.queue_adapter).to receive(:enqueue_at).and_wrap_original do |original, *values|
        pushes += 1
        raise RedisClient::CannotConnectError, 'redis down' if pushes == 2

        original.call(*values)
      end
      expect(JobCommands.rehome!(type, by: 'spec'))
        .to eq(moved: 1, left: 1, error: 'RedisClient::CannotConnectError')
      queued = enqueued_jobs.sole
      ids = [payload.fetch('source_job_id'), second.fetch('source_job_id')]
      expect(ids).to include(queued.fetch('job_id'))
      remaining = (ids - [queued.fetch('job_id')]).sole
      expect(JobOutbox.where(command_type: type).sole.event_id).to eq(remaining)
      expect(Time.iso8601(queued.fetch('scheduled_at'))).to eq(due)
      expect(queued.fetch('timezone')).to eq('Asia/Tokyo') unless type == 'stats.full_recalculation'
      expected = serialized(klass, args, kwargs, payload)
      expect(queued.fetch('arguments')).to eq(expected.fetch('arguments'))
      expect(queued['continuation']).to eq(progress) if type == 'points.anomaly_backfill'
      expect(JobCommands.rehome!(type, by: 'spec')).to eq(moved: 1, left: 0)
      expect(enqueued_jobs.last.fetch('job_id')).to eq(remaining)
      clear_enqueued_jobs
      reverse.call(payload.merge('run_at' => due.to_i))
      expect(enqueued_jobs.sole.fetch('job_id')).to eq(payload.fetch('source_job_id'))
    end
  end
end
