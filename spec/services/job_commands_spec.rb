# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobCommands do
  let(:trip_payload) { { 'trip_id' => 42, 'distance_unit' => 'km' } }

  it 'immich producer queues after commit and retains failed rehome events' do
    payload = { 'user_id' => 987_001, 'time_zone' => Time.zone.name }
    job_owner!('command:imports.immich_geodata', :sidekiq)
    ActiveRecord::Base.transaction do
      JobCommands.produce('imports.immich_geodata', payload, aggregate_id: 987_001, producer: 'spec')
      expect(enqueued_jobs).to eq([])
      raise ActiveRecord::Rollback
    end
    expect(enqueued_jobs).to eq([])
    job_owner!('command:imports.immich_geodata', :oban)
    event = SecureRandom.uuid
    2.times do
      JobCommands.forward('imports.immich_geodata', payload, event_id: event, aggregate_id: 987_001, producer: 'spec')
    end
    expect(JobOutbox.count).to eq(1)
    allow(Import::ImmichGeodataJob.queue_adapter).to receive(:enqueue_at).and_raise(RedisClient::CannotConnectError)
    expect(JobCommands.rehome!('imports.immich_geodata', by: 'spec'))
      .to eq({ moved: 0, left: 1, error: 'RedisClient::CannotConnectError' })
    expect(JobOutbox.find(event).state).to eq('pending')
    allow(Import::ImmichGeodataJob.queue_adapter).to receive(:enqueue_at).and_call_original
    expect(JobCommands.rehome!('imports.immich_geodata', by: 'spec')).to eq({ moved: 1, left: 0 })
    expect(JobOutbox.exists?(event)).to be(false)
    expect(enqueued_jobs.last[:args]).to eq([987_001])
  end

  def produce_trip
    described_class.produce('trips.calculate', trip_payload, aggregate_id: 42, dedupe_key: '42', producer: 'spec')
  end

  it 'enqueues the Sidekiq job when Phoenix never migrated the database' do
    expect { expect(produce_trip).to eq(:sidekiq) }.to have_enqueued_job(Trips::CalculateAllJob).with(42, 'km')
    expect(JobOutbox.count).to eq(0)
  end

  it 'enqueues the Sidekiq job while Sidekiq owns the key' do
    job_owner!('command:trips.calculate', :sidekiq)

    expect { produce_trip }.to have_enqueued_job(Trips::CalculateAllJob)
  end

  it 'writes a typed command instead when Oban owns the key' do
    job_owner!('command:trips.calculate', :oban)

    expect { expect(produce_trip).to eq(:outbox) }.not_to have_enqueued_job
    row = JobOutbox.sole
    expect(row).to have_attributes(command_type: 'trips.calculate', command_version: 1, payload: trip_payload,
                                   aggregate_id: 42, dedupe_key: '42', state: 'pending',
                                   metadata: { 'producer' => 'spec' })
  end

  it 'joins the caller transaction, so a rolled-back domain write produces nothing' do
    job_owner!('command:trips.calculate', :oban)

    ActiveRecord::Base.transaction do
      produce_trip
      raise ActiveRecord::Rollback
    end

    expect(JobOutbox.count).to eq(0)
  end

  it 'collapses repeated commands for the same pending trip' do
    job_owner!('command:trips.calculate', :oban)

    3.times { produce_trip }

    expect(JobOutbox.pending.count).to eq(1)
  end

  it 'forwards an event once however often a Sidekiq retry forwards it' do
    event_id = SecureRandom.uuid
    args = [{ 'user_id' => 1, 'locale' => 'de' }, { event_id:, aggregate_id: 1, producer: 'spec' }]

    expect(described_class.forward('users.explore_features_mail', args[0], **args[1])).to eq(1)
    expect(described_class.forward('users.explore_features_mail', args[0], **args[1])).to eq(0)
  end

  it 'registers achievements.check and areas.relabel_visits at version 1' do
    versions = described_class::COMMANDS.slice('achievements.check', 'areas.relabel_visits')
                                        .transform_values { _1.fetch(:version) }

    expect(versions).to eq('achievements.check' => 1, 'areas.relabel_visits' => 1)
  end

  it 'each wave-5 lambda enqueues today’s job with its delay' do
    user = create(:user)
    track = create(:track, user: user)
    at = Time.zone.parse('2026-03-29 12:34:56 UTC')
    range_payload = Tracks::GenerationCommand.payload(user.id, start_at: at, end_at: at + 1.hour, mode: :daily,
                                                               untracked_only: false, import_id: nil, job_queue: nil)

    described_class::COMMANDS.fetch('tracks.generate_range').fetch(:sidekiq).call(range_payload, at)
    described_class::COMMANDS.fetch('tracks.generate_realtime').fetch(:sidekiq).call({ 'user_id' => user.id }, at)
    described_class::COMMANDS.fetch('tracks.recalculate').fetch(:sidekiq).call({ 'track_id' => track.id }, at)
    described_class::COMMANDS.fetch('transportation.reclassify_track').fetch(:sidekiq).call(
      { 'track_id' => track.id, 'report_progress' => true, 'user_id' => user.id }, at
    )

    expect(Tracks::ParallelGeneratorJob).to have_been_enqueued.with(user.id, hash_including(mode: :daily)).at(at)
    expect(Tracks::RealtimeGenerationJob).to have_been_enqueued.with(user.id).at(at)
    expect(Tracks::RecalculateJob).to have_been_enqueued.with(track.id).at(at)
    expect(TransportationModes::ReclassifyTrackJob).to have_been_enqueued
      .with(track.id, report_progress: true, user_id: user.id).at(at)
  end

  it 'rehome moves pending wave-5 rows to their jobs' do
    user = create(:user)
    track = create(:track, user: user)
    at = Time.zone.parse('2026-03-29 12:34:56 UTC')
    range_payload = Tracks::GenerationCommand.payload(user.id, start_at: at, end_at: at + 1.hour, mode: :daily,
                                                               untracked_only: false, import_id: nil, job_queue: nil)
    payloads = {
      'tracks.generate_range' => [range_payload, user.id],
      'tracks.generate_realtime' => [{ 'user_id' => user.id }, user.id],
      'tracks.recalculate' => [{ 'track_id' => track.id }, track.id],
      'transportation.reclassify_track' => [
        { 'track_id' => track.id, 'report_progress' => true, 'user_id' => user.id }, track.id
      ]
    }

    payloads.each do |type, (payload, aggregate_id)|
      job_owner!("command:#{type}", :oban)
      described_class.forward(type, payload, event_id: SecureRandom.uuid, aggregate_id:, producer: 'spec',
                              scheduled_at: at)
      expect(described_class.rehome!(type, by: 'spec')).to eq({ moved: 1, left: 0 })
    end

    expect(JobOutbox.pending).to be_empty
    expect(enqueued_jobs.map { _1[:job] }).to include(Tracks::ParallelGeneratorJob, Tracks::RealtimeGenerationJob,
                                                      Tracks::RecalculateJob, TransportationModes::ReclassifyTrackJob)
  end

  it "each wave-5b lambda enqueues today's job with its delay" do
    user = create(:user)
    at = Time.zone.parse('2026-03-29 12:34:56 UTC')
    zone = ActiveSupport::TimeZone['Europe/Berlin']
    calendar_payload = { 'user_id' => user.id, 'start_at' => 1_700_000_000, 'end_at' => 1_700_003_600,
                        'stepping' => 'calendar', 'time_zone' => 'Europe/Berlin', 'plan_restricted' => false }
    fixed_payload = calendar_payload.merge('stepping' => 'fixed')

    point_lambda = described_class::COMMANDS.fetch('geocoding.reverse_point').fetch(:sidekiq)
    expect { point_lambda.call({ 'user_id' => user.id, 'point_ids' => [11, 12], 'force' => false }, at) }
      .to have_enqueued_job(ReverseGeocodingJob).with('Point', 11, force: false)
                                                .and have_enqueued_job(ReverseGeocodingJob)
      .with('Point', 12, force: false)

    place_lambda = described_class::COMMANDS.fetch('geocoding.reverse_place').fetch(:sidekiq)
    expect { place_lambda.call({ 'place_id' => 77 }, at) }
      .to have_enqueued_job(ReverseGeocodingJob).with('place', 77).at(at)

    suggest_lambda = described_class::COMMANDS.fetch('visits.suggest').fetch(:sidekiq)
    expect { suggest_lambda.call(calendar_payload, at) }
      .to have_enqueued_job(VisitSuggestingJob)
      .with(user_id: user.id, start_at: zone.at(1_700_000_000).iso8601, end_at: zone.at(1_700_003_600).iso8601).at(at)
    expect { suggest_lambda.call(fixed_payload, at) }
      .to have_enqueued_job(VisitSuggestingJob)
      .with(user_id: user.id, start_at: zone.at(1_700_000_000), end_at: zone.at(1_700_003_600)).at(at)

    redetect_lambda = described_class::COMMANDS.fetch('visits.full_history_redetect').fetch(:sidekiq)
    expect { redetect_lambda.call({ 'user_id' => user.id, 'time_zone' => 'UTC', 'plan_restricted' => false }, at) }
      .to have_enqueued_job(Visits::FullHistoryRedetectJob).with(user.id).at(at)

    extract_lambda = described_class::COMMANDS.fetch('enhanced_import.extract_gpx').fetch(:sidekiq)
    expect { extract_lambda.call({ 'import_id' => 555, 'lock_attempt' => 3 }, at) }
      .to have_enqueued_job(EnhancedImport::ExtractJob).with(555, attempt: 3).at(at)

    destroy_lambda = described_class::COMMANDS.fetch('enhanced_import.destroy_gpx').fetch(:sidekiq)
    expect { destroy_lambda.call({ 'import_id' => 555 }, at) }
      .to have_enqueued_job(EnhancedImport::DestroyJob).with(555).at(at)
  end

  it 'wave-5b lambdas enqueue after commit' do
    user = create(:user)
    payloads = {
      'geocoding.reverse_point' => { 'user_id' => user.id, 'point_ids' => [31], 'force' => false },
      'geocoding.reverse_place' => { 'place_id' => 99 },
      'visits.suggest' => { 'user_id' => user.id, 'start_at' => 1_700_000_000, 'end_at' => 1_700_003_600,
                            'stepping' => 'fixed', 'time_zone' => 'UTC', 'plan_restricted' => false },
      'visits.full_history_redetect' => { 'user_id' => user.id, 'time_zone' => 'UTC', 'plan_restricted' => false },
      'enhanced_import.extract_gpx' => { 'import_id' => 555, 'lock_attempt' => 1 },
      'enhanced_import.destroy_gpx' => { 'import_id' => 555 }
    }

    payloads.each do |type, payload|
      ActiveRecord::Base.transaction do
        described_class::COMMANDS.fetch(type).fetch(:sidekiq).call(payload, Time.current)
        raise ActiveRecord::Rollback
      end
    end

    expect(enqueued_jobs).to be_empty
  end

  it 'rehome moves pending wave-5b rows to their jobs' do
    user = create(:user)
    at = Time.zone.parse('2026-03-29 12:34:56 UTC')
    payloads = {
      'geocoding.reverse_point' => [{ 'user_id' => user.id, 'point_ids' => [21, 22], 'force' => false }, user.id],
      'geocoding.reverse_place' => [{ 'place_id' => 88 }, user.id],
      'visits.suggest' => [{ 'user_id' => user.id, 'start_at' => 1_700_000_000, 'end_at' => 1_700_003_600,
                            'stepping' => 'fixed', 'time_zone' => 'UTC', 'plan_restricted' => false }, user.id],
      'visits.full_history_redetect' => [{ 'user_id' => user.id, 'time_zone' => 'UTC', 'plan_restricted' => false },
                                         user.id],
      'enhanced_import.extract_gpx' => [{ 'import_id' => 555, 'lock_attempt' => 2 }, user.id],
      'enhanced_import.destroy_gpx' => [{ 'import_id' => 555 }, user.id]
    }

    payloads.each do |type, (payload, aggregate_id)|
      job_owner!("command:#{type}", :oban)
      described_class.forward(type, payload, event_id: SecureRandom.uuid, aggregate_id:, producer: 'spec',
                              scheduled_at: at)
      expect(described_class.rehome!(type, by: 'spec')).to eq({ moved: 1, left: 0 })
    end

    expect(JobOutbox.pending).to be_empty
    expect(enqueued_jobs.map { _1[:job] }).to match_array(
      [ReverseGeocodingJob, ReverseGeocodingJob, ReverseGeocodingJob, VisitSuggestingJob,
       Visits::FullHistoryRedetectJob, EnhancedImport::ExtractJob, EnhancedImport::DestroyJob]
    )
  end

  it 'stats.calculate_month enqueues the month with its delay; rehome keeps an unsent row when the push fails' do
    user = create(:user)
    at = Time.zone.parse('2026-03-29 12:34:56 UTC')
    payload = { 'user_id' => user.id, 'year' => 2024, 'month' => 3, 'notify_on_failure' => false }

    described_class::COMMANDS.fetch('stats.calculate_month').fetch(:sidekiq).call(payload, at)
    expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2024, 3, notify_on_failure: false).at(at)

    job_owner!('command:stats.calculate_month', :oban)
    2.times do
      described_class.forward('stats.calculate_month', payload, event_id: SecureRandom.uuid, aggregate_id: user.id,
                                                                producer: 'spec', scheduled_at: at)
    end
    pushes = 0
    %i[enqueue enqueue_at].each do |push|
      allow(ApplicationJob.queue_adapter).to receive(push).and_wrap_original do |original, *args|
        pushes += 1
        raise RedisClient::CannotConnectError, 'redis down' if pushes == 2

        original.call(*args)
      end
    end

    expect(described_class.rehome!('stats.calculate_month', by: 'spec'))
      .to eq({ moved: 1, left: 1, error: 'RedisClient::CannotConnectError' })
    expect(described_class.rehome!('stats.calculate_month', by: 'spec')).to eq({ moved: 1, left: 0 })
  end

  it 're-homes pending achievement and relabel commands to their Sidekiq jobs' do
    user = create(:user)
    area = create(:area, user: user)
    job_owner!('command:achievements.check', :oban)
    job_owner!('command:areas.relabel_visits', :oban)
    described_class.forward('achievements.check', { 'user_id' => user.id, 'notify' => true, 'oldest_timestamp' => 50 },
                            event_id: SecureRandom.uuid, aggregate_id: user.id, producer: 'spec')
    described_class.forward('areas.relabel_visits', { 'area_id' => area.id }, event_id: SecureRandom.uuid,
                            aggregate_id: area.id, dedupe_key: area.id.to_s, producer: 'spec')

    expect { described_class.rehome!('achievements.check', by: 'spec') }
      .to have_enqueued_job(Achievements::CheckJob).with(user.id, notify: true, oldest_timestamp: 50)
    expect { described_class.rehome!('areas.relabel_visits', by: 'spec') }
      .to have_enqueued_job(Areas::RelabelVisitsJob).with(area.id)
    expect(JobOutbox.pending.count).to eq(0)
  end

  it 'cancels only the pending commands of one aggregate' do
    job_owner!('command:users.explore_features_mail', :oban)
    %w[7 8].each do |id|
      described_class.produce('users.explore_features_mail', { 'user_id' => id.to_i, 'locale' => 'en' },
                              aggregate_id: id.to_i, scheduled_at: 2.days.from_now, producer: 'spec')
    end

    expect(described_class.cancel_pending('users.explore_features_mail', 7)).to eq(1)
    expect(JobOutbox.pluck(:aggregate_id)).to eq([8])
  end

  it 're-homes pending commands to Sidekiq with their schedule and locale, and leaves dispatched ones' do
    job_owner!('command:users.explore_features_mail', :oban)
    at = 2.days.from_now.change(usec: 0)
    described_class.produce('users.explore_features_mail', { 'user_id' => 5, 'locale' => 'de' },
                            aggregate_id: 5, scheduled_at: at, producer: 'spec')
    JobOutbox.create!(event_id: SecureRandom.uuid, command_type: 'users.explore_features_mail', command_version: 1,
                      payload: { 'user_id' => 6, 'locale' => 'en' }, scheduled_at: at, state: 'dispatched')

    expect do
      expect(described_class.rehome!('users.explore_features_mail', by: 'spec')).to eq({ moved: 1, left: 0 })
    end
      .to have_enqueued_job(Users::MailerSendingJob).with(5, 'explore_features').at(at)
    expect(enqueued_jobs.last['locale']).to eq('de')
    expect(JobOutbox.pluck(:state)).to eq(['dispatched'])
  end

  it 'leaves a pending command with a mismatched command_version untouched' do
    job_owner!('command:trips.calculate', :oban)
    produce_trip
    JobOutbox.update_all(command_version: 2)

    expect { expect(described_class.rehome!('trips.calculate', by: 'spec')).to eq({ moved: 0, left: 0 }) }
      .not_to have_enqueued_job(Trips::CalculateAllJob)
    expect(JobOutbox.pluck(:command_version, :state)).to eq([[2, 'pending']])
  end

  it 'releases the key to a pinned Sidekiq owner in the same transaction, so the re-homed job runs in Sidekiq' do
    job_owner!('command:users.explore_features_mail', :oban)
    described_class.produce('users.explore_features_mail', { 'user_id' => 5, 'locale' => 'en' },
                            aggregate_id: 5, scheduled_at: 2.days.from_now, producer: 'spec')

    described_class.rehome!('users.explore_features_mail', by: 'spec')

    owner = ActiveRecord::Base.connection.select_rows(
      "SELECT owner, pinned, updated_by FROM phoenix.job_owners WHERE key = 'command:users.explore_features_mail'"
    )
    expect(owner).to eq([['sidekiq', true, 'spec']])
    expect(JobOwnership.with_owner('command:users.explore_features_mail') { :sidekiq_runs }).to eq(:sidekiq_runs)
  end

  {
    'exports.points' => ->(id) { { 'export_id' => id, 'user_id' => 1 } },
    'mail.family_lapse' => ->(id) { { 'user_id' => id, 'family_id' => 1, 'locale' => 'de', 'lapse_at' => 'none' } }
  }.each do |type, payload|
    it "re-homes #{type} inline, so an enqueue error keeps the unsent command for the next run" do
      job_owner!("command:#{type}", :oban)
      [1, 2].each do |id|
        described_class.forward(type, payload.call(id), event_id: SecureRandom.uuid, aggregate_id: id, producer: 'spec')
      end
      pushes = 0
      allow(ExportJob.queue_adapter).to receive(:enqueue).and_wrap_original do |original, job|
        pushes += 1
        raise RedisClient::CannotConnectError, 'redis down' if pushes == 2

        original.call(job)
      end

      expect(described_class.rehome!(type, by: 'spec'))
        .to eq({ moved: 1, left: 1, error: 'RedisClient::CannotConnectError' })
      expect([JobOutbox.pending.count, enqueued_jobs.size]).to eq([1, 1])

      expect(described_class.rehome!(type, by: 'spec')).to eq({ moved: 1, left: 0 })
      expect([JobOutbox.count, enqueued_jobs.size]).to eq([0, 2])
    end
  end

  it 'replays only quarantined commands, keeping the event id and auditing who and why' do
    phoenix_tables!
    row = JobOutbox.create!(event_id: SecureRandom.uuid, command_type: 'trips.calculate', command_version: 1,
                            payload: trip_payload, scheduled_at: Time.current, state: 'quarantined',
                            error_code: 'unsupported_version')

    described_class.replay!(row.event_id, actor: 'rake:eugene', reason: 'decoder fixed')

    expect(row.reload).to have_attributes(state: 'pending', error_code: nil)
    expect(ActiveRecord::Base.connection.select_rows('SELECT actor, reason FROM phoenix.job_outbox_replays'))
      .to eq([['rake:eugene', 'decoder fixed']])
    expect { described_class.replay!(row.event_id, actor: 'x', reason: 'y') }.to raise_error(ArgumentError, /pending/)
  end

  describe 'rehome! while a relay holds a pending command' do
    self.use_transactional_tests = false

    let(:event_ids) { [SecureRandom.uuid, SecureRandom.uuid] }

    after do
      JobOutbox.where(event_id: event_ids).delete_all
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '2s'")
        ActiveRecord::Base.connection.execute('DROP SCHEMA IF EXISTS phoenix CASCADE')
      end
      PhoenixTables.install_state!
    end

    it 'moves unlocked commands and reports the pending command left behind by the relay' do
      job_owner!('command:trips.calculate', :oban)
      event_ids.each_with_index do |event_id, index|
        described_class.forward('trips.calculate', { 'trip_id' => index + 1, 'distance_unit' => 'km' }, event_id:,
                                aggregate_id: index + 1, producer: 'spec')
      end
      holding = Queue.new
      release = Queue.new
      holder = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.transaction do
            connection.execute("SET LOCAL lock_timeout = '2s'")
            connection.execute("SELECT 1 FROM job_outbox WHERE event_id = '#{event_ids.first}' FOR UPDATE")
            holding << true
            release.pop
          end
        end
      end

      begin
        Timeout.timeout(5) { holding.pop }

        expect do
          expect(described_class.rehome!('trips.calculate', by: 'spec')).to eq({ moved: 1, left: 1 })
        end.to have_enqueued_job(Trips::CalculateAllJob).with(2, 'km')
        expect(JobOutbox.where(event_id: event_ids)).to contain_exactly(
          have_attributes(event_id: event_ids.first, state: 'pending')
        )
      ensure
        release << true
        raise 'holder thread did not finish: still holding the outbox row lock' unless holder.join(5)
      end
    end
  end

  describe 'produce joining the caller transaction across a real commit/rollback' do
    self.use_transactional_tests = false

    after do
      JobOutbox.where(command_type: 'trips.calculate', aggregate_id: 42).delete_all
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '2s'")
        ActiveRecord::Base.connection.execute('DROP SCHEMA IF EXISTS phoenix CASCADE')
      end
      PhoenixTables.install_state!
    end

    it 'leaves no outbox row when the caller transaction rolls back' do
      job_owner!('command:trips.calculate', :oban)

      ActiveRecord::Base.transaction do
        produce_trip
        raise ActiveRecord::Rollback
      end

      expect(JobOutbox.count).to eq(0)
    end

    it 'writes exactly one outbox row when the caller transaction commits' do
      job_owner!('command:trips.calculate', :oban)

      ActiveRecord::Base.transaction { produce_trip }

      expect(JobOutbox.count).to eq(1)
    end
  end
end
