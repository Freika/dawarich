# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Release command routers' do
  it 'A12rel parents forward with stable identity only under their exact owner keys' do
    import = create(:import, source: :csv)
    at = 1.hour.from_now.change(usec: 0)
    samples = [
      [DataMigrations::BackfillAchievementsJob, [], 'release.achievements_backfill', {}],
      [TransportationModes::ImportBackfillJob, [import.id], 'release.import_backfill',
       { 'import_id' => import.id, 'ambient_zone' => 'Asia/Tokyo' }]
    ]
    samples.each do |klass, arguments, type, payload|
      Time.use_zone('Asia/Tokyo') do
        [nil, :sidekiq, :oban].each do |owner|
          phoenix_tables!
          JobOutbox.delete_all
          JobOwnership.release!("command:#{type}", by: 'spec')
          job_owner!("command:#{type}", owner) if owner
          job_owner!('command:achievements.bulk_check', owner == :oban ? :sidekiq : :oban)
          job = klass.new(*arguments)
          job.scheduled_at = at
          RSpec::Mocks.with_temporary_scope do
            if owner == :oban
              expect(Country).not_to receive(:none?) if arguments.empty?
              expect(Import).not_to receive(:find_by) unless arguments.empty?
              expect { 2.times { job.perform_now } }.not_to have_enqueued_job
              expect(JobOutbox.sole).to have_attributes(command_type: type, event_id: job.job_id,
                                                        payload:, scheduled_at: at, aggregate_id: nil)
            else
              expect(Country).to receive(:none?).and_call_original if arguments.empty?
              expect(Import).to receive(:find_by).with(id: import.id).and_call_original unless arguments.empty?
              job.perform_now
              expect(JobOutbox.count).to eq(0)
            end
          end
        end
      end
    end
  end

  rows = [
    { job: DataMigrations::BackfillPointDimensionsJob, args: [nil, 50_000], kwargs: {},
      type: 'release.point_dimensions_country',
      payload: { 'phase' => 'dimensions', 'start_id' => nil, 'batch_size' => 50_000, 'repair_collisions' => false },
      aggregate: nil },
    { job: DataMigrations::BackfillPointCountryIdJob, args: [7, 25_000], kwargs: { repair_collisions: true },
      type: 'release.point_dimensions_country',
      payload: { 'phase' => 'country', 'start_id' => 7, 'batch_size' => 25_000, 'repair_collisions' => true },
      aggregate: nil },
    { job: DataMigrations::FixRouteOpacityJob, args: [], kwargs: {}, type: 'release.route_opacity',
      payload: {}, aggregate: nil },
    { job: DataMigrations::BackfillOnboardingCompletedJob, args: [], kwargs: {}, type: 'release.onboarding_completed',
      payload: {}, aggregate: nil },
    { job: DataMigrations::DestroyOrphanedTracksJob, args: [], kwargs: {}, type: 'release.orphaned_tracks',
      payload: {}, aggregate: nil },
    { job: Tracks::DeduplicationJob, args: [42], kwargs: {}, type: 'release.tracks_dedup',
      payload: { 'user_id' => 42 }, aggregate: 42 },
    { job: DataMigrations::BackfillPlaceNameLocksJob, args: [], kwargs: {}, type: 'release.place_name_locks',
      payload: {}, aggregate: nil },
    { job: TrackSegments::TimeAnchorBackfillJob, args: [11], kwargs: {}, type: 'release.time_anchor',
      payload: { 'from_id' => 11 }, aggregate: nil },
    { job: DataMigrations::BackfillTransportationModesJob, args: [5], kwargs: {}, type: 'release.transportation',
      payload: { 'scope' => 'missing', 'from_track_id' => 5 }, aggregate: nil },
    { job: TransportationModes::FleetReclassifyJob, args: [5], kwargs: {}, type: 'release.transportation',
      payload: { 'scope' => 'all', 'from_track_id' => 5 }, aggregate: nil },
    { job: Visits::FleetRedetectJob, args: [], kwargs: {}, type: 'release.visits_fleet_redetect',
      payload: {}, aggregate: nil },
    { job: DataMigrations::CleanupNullIslandJob, args: [], kwargs: {}, type: 'release.null_island',
      payload: { 'user_id' => nil }, aggregate: nil },
    { job: DataMigrations::CleanupNullIslandJob, args: [42], kwargs: {}, type: 'release.null_island',
      payload: { 'user_id' => 42 }, aggregate: 42 },
    { job: DataMigrations::BackfillMotionDataJob, args: [], kwargs: { batch_size: 500 }, type: 'release.motion_data',
      payload: { 'batch_size' => 500 }, aggregate: nil },
    { job: DataMigrations::BackfillAltitudeJob, args: [], kwargs: {}, type: 'release.altitude',
      payload: {}, aggregate: nil }
  ]

  rows.each do |row|
    it "Oban-owned: #{row[:job].name}#{row[:args].inspect} forwards once with its job id and enqueues nothing" do
      job_owner!("command:#{row[:type]}", :oban)
      job = row[:job].new(*row[:args], **row[:kwargs])

      expect { 2.times { job.perform_now } }.not_to have_enqueued_job
      expect(JobOutbox.sole).to have_attributes(
        command_type: row[:type], payload: row[:payload], event_id: job.job_id,
        aggregate_id: row[:aggregate], metadata: { 'producer' => row[:job].name }
      )
    end
  end

  it 'Oban-owned route opacity leaves the user unchanged' do
    user = create(:user, settings: { 'route_opacity' => 50 })
    job_owner!('command:release.route_opacity', :oban)

    DataMigrations::FixRouteOpacityJob.perform_now

    expect(user.reload.settings['route_opacity']).to eq(50)
  end

  it 'Oban-owned null-island child leaves the point unflagged' do
    user = create(:user)
    point = create(:point, user:, longitude: 0.01, latitude: 0.01)
    job_owner!('command:release.null_island', :oban)

    DataMigrations::CleanupNullIslandJob.perform_now(user.id)

    expect(point.reload.anomaly).not_to be(true)
  end

  it 'Oban-owned dimensions page stamps nothing' do
    point = create(:point)
    job_owner!('command:release.point_dimensions_country', :oban)

    DataMigrations::BackfillPointDimensionsJob.perform_now

    expect([point.reload.source_id, PointSource.count]).to eq([nil, 0])
  end
end
