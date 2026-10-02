# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReleaseCommands do
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
    expect(described_class::COMMANDS.keys).to match_array(samples.keys)
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
