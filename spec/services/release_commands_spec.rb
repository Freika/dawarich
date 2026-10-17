# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReleaseCommands do
  it 'A12rel rehome and reverse bulk retain source arguments and scheduled time' do
    payload = { 'import_id' => 54_001, 'ambient_zone' => 'Asia/Tokyo' }
    samples = [
      ['release.achievements_backfill', {}, DataMigrations::BackfillAchievementsJob, []],
      ['release.import_backfill', payload, TransportationModes::ImportBackfillJob, [54_001]]
    ]
    samples.each do |type, data, klass, arguments|
      command = JobCommands::COMMANDS.fetch(type)
      expect(command.fetch(:version)).to eq(1)
      expect { command.fetch(:sidekiq).call(data, at) }.to have_enqueued_job(klass).with(*arguments).at(at)
      expect(enqueued_jobs.last['timezone'])
        .to eq(type == 'release.import_backfill' ? 'Asia/Tokyo' : Time.zone.name)
      clear_enqueued_jobs
      job_owner!("command:#{type}", :oban)
      JobCommands.forward(type, data, event_id: SecureRandom.uuid, aggregate_id: nil, producer: 'spec',
scheduled_at: at)
      expect { expect(JobCommands.rehome!(type, by: 'spec')).to eq({ moved: 1, left: 0 }) }
        .to have_enqueued_job(klass).with(*arguments).at(at)
      expect(JobOutbox.count).to eq(0)
      clear_enqueued_jobs
    end

    job_id = '2ce791c6-a6d3-57d0-a80b-f180c7944093'
    root = 'e18e8b6f-370a-5f22-a306-3291938cd8c5'
    options = { 'notify' => false, 'force' => true, 'stale_only' => true }
    reverse = { 'job_id' => job_id, 'options' => options, 'run_at' => at.iso8601(6) }
    %i[sidekiq oban].each do |owner|
      job_owner!('command:achievements.bulk_check', owner)
      job_owner!('command:achievements.check', owner == :oban ? :sidekiq : :oban)
      expect { RailsCommands::Registry::HANDLERS.fetch('release_achievements_bulk_check').fetch(:call).call(reverse) }
        .to have_enqueued_job(Achievements::BulkCheckJob).with(**options.symbolize_keys).at(at)
      serialized = enqueued_jobs.last
      expect(serialized['job_id']).to eq(job_id)
      expect(Achievements::BulkCommands.root(job_id, nil)).to eq(root)
      if owner == :oban
        ActiveJob::Base.deserialize(serialized).perform_now
        expect(JobOutbox.sole).to have_attributes(event_id: root, command_type: 'achievements.bulk_check',
                                                  payload: options)
        JobOutbox.delete_all
      end
      clear_enqueued_jobs
    end
  end

  samples = {
    'release.point_dimensions_country' => [
      [{ 'phase' => 'dimensions', 'start_id' => nil, 'batch_size' => 50_000, 'repair_collisions' => false },
       DataMigrations::BackfillPointDimensionsJob, [nil, 50_000], {}],
      [{ 'phase' => 'country', 'start_id' => 7, 'batch_size' => 25_000, 'repair_collisions' => true },
       DataMigrations::BackfillPointCountryIdJob, [7, 25_000], { repair_collisions: true }]
    ],
    'release.route_opacity' => [[{}, DataMigrations::FixRouteOpacityJob, [], {}]],
    'release.onboarding_completed' => [[{}, DataMigrations::BackfillOnboardingCompletedJob, [], {}]],
    'release.orphaned_tracks' => [[{}, DataMigrations::DestroyOrphanedTracksJob, [], {}]],
    'release.tracks_dedup' => [[{ 'user_id' => 42 }, Tracks::DeduplicationJob, [42], {}]],
    'release.place_name_locks' => [[{}, DataMigrations::BackfillPlaceNameLocksJob, [], {}]],
    'release.time_anchor' => [[{ 'from_id' => 11 }, TrackSegments::TimeAnchorBackfillJob, [11], {}]],
    'release.transportation' => [
      [{ 'scope' => 'missing', 'from_track_id' => 5 }, DataMigrations::BackfillTransportationModesJob, [5], {}],
      [{ 'scope' => 'all', 'from_track_id' => 5 }, TransportationModes::FleetReclassifyJob, [5], {}]
    ],
    'release.visits_fleet_redetect' => [[{}, Visits::FleetRedetectJob, [], {}]],
    'release.null_island' => [
      [{ 'user_id' => 42 }, DataMigrations::CleanupNullIslandJob, [42], {}],
      [{ 'user_id' => nil }, DataMigrations::CleanupNullIslandJob, [nil], {}]
    ],
    'release.motion_data' => [
      [{ 'batch_size' => 500 }, DataMigrations::BackfillMotionDataJob, [], { batch_size: 500 }]
    ],
    'release.altitude' => [[{}, DataMigrations::BackfillAltitudeJob, [], {}]]
  }

  let(:at) { 1.hour.from_now.change(usec: 0) }

  it 'every release lambda enqueues its job at the given time' do
    samples.each do |type, cases|
      cases.each do |payload, job, args, kwargs|
        expect { described_class::COMMANDS.fetch(type).fetch(:sidekiq).call(payload, at) }
          .to have_enqueued_job(job).with(*args, **kwargs).at(at)
        expect(ActiveJob::Arguments.deserialize(enqueued_jobs.last[:args]))
          .to eq(kwargs.empty? ? args : [*args, kwargs])
      end
    end
  end

  it 'JobCommands serves every release type' do
    expect(JobCommands::COMMANDS.keys).to include(*described_class::COMMANDS.keys)
    expect(described_class::COMMANDS.keys)
      .to match_array(samples.keys + %w[release.anomalies release.anomalies_user release.per_tracker])
  end

  it 'rehome moves a pending release row to Sidekiq with its delay' do
    job_owner!('command:release.time_anchor', :oban)
    JobCommands.forward('release.time_anchor', { 'from_id' => 11 }, event_id: SecureRandom.uuid, aggregate_id: nil,
                                                                     producer: 'spec', scheduled_at: at)

    expect { expect(JobCommands.rehome!('release.time_anchor', by: 'spec')).to eq({ moved: 1, left: 0 }) }
      .to have_enqueued_job(TrackSegments::TimeAnchorBackfillJob).with(11).at(at)
    expect(JobOutbox.count).to eq(0)
  end

  samples.each do |type, cases|
    it "rehome keeps an unsent #{type} row when the push fails" do
      payload = cases.first.first
      job_owner!("command:#{type}", :oban)
      2.times do
        JobCommands.forward(type, payload, event_id: SecureRandom.uuid, aggregate_id: nil, producer: 'spec')
      end
      pushes = 0
      %i[enqueue enqueue_at].each do |push|
        allow(ApplicationJob.queue_adapter).to receive(push).and_wrap_original do |original, *args|
          pushes += 1
          raise RedisClient::CannotConnectError, 'redis down' if pushes == 2

          original.call(*args)
        end
      end

      expect(JobCommands.rehome!(type, by: 'spec'))
        .to eq({ moved: 1, left: 1, error: 'RedisClient::CannotConnectError' })
      expect([JobOutbox.pending.count, enqueued_jobs.size]).to eq([1, 1])

      expect(JobCommands.rehome!(type, by: 'spec')).to eq({ moved: 1, left: 0 })
      expect([JobOutbox.count, enqueued_jobs.size]).to eq([0, 2])
    end
  end

  it 'a release lambda called inside a transaction enqueues after commit' do
    inside = ActiveRecord::Base.transaction do
      described_class::COMMANDS.fetch('release.altitude').fetch(:sidekiq).call({}, at)
      enqueued_jobs.size
    end

    expect(inside).to eq(0)
    expect(DataMigrations::BackfillAltitudeJob).to have_been_enqueued.at(at)
  end

  it 'forwarded? is false and writes nothing while Sidekiq owns the key' do
    phoenix_tables!

    expect(described_class.forwarded?(DataMigrations::BackfillAltitudeJob.new, 'release.altitude', {})).to be(false)
    expect(JobOutbox.count).to eq(0)
  end
end
