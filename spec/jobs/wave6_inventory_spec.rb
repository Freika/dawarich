# frozen_string_literal: true

require 'rails_helper'

module Wave6Inventory
  RELEASE = {
    'DataMigrations::BackfillPointDimensionsJob' => 'release.point_dimensions_country',
    'DataMigrations::BackfillPointCountryIdJob' => 'release.point_dimensions_country',
    'DataMigrations::FixRouteOpacityJob' => 'release.route_opacity',
    'DataMigrations::BackfillOnboardingCompletedJob' => 'release.onboarding_completed',
    'DataMigrations::DestroyOrphanedTracksJob' => 'release.orphaned_tracks',
    'Tracks::DeduplicationJob' => 'release.tracks_dedup',
    'DataMigrations::BackfillPlaceNameLocksJob' => 'release.place_name_locks',
    'TrackSegments::TimeAnchorBackfillJob' => 'release.time_anchor',
    'DataMigrations::BackfillTransportationModesJob' => 'release.transportation',
    'TransportationModes::FleetReclassifyJob' => 'release.transportation',
    'Visits::FleetRedetectJob' => 'release.visits_fleet_redetect',
    'DataMigrations::CleanupNullIslandJob' => 'release.null_island',
    'DataMigrations::BackfillMotionDataJob' => 'release.motion_data',
    'DataMigrations::BackfillAltitudeJob' => 'release.altitude'
  }.freeze

  OTHER = {
    'DataMigrations::StartSettingsPointsCountryIdsJob' => :retire,
    'DataMigrations::SetPointsCountryIdsJob' => :retire,
    'DataMigrations::SetReverseGeocodedAtForPointsJob' => :retire,
    'DataMigrations::MigratePlacesLonlatJob' => :retire,
    'DataMigrations::BackfillCountryNameJob' => :retire,
    'DataMigrations::PrefillPointsCounterCacheJob' => :retire,
    'Users::ResetPointsCounterJob' => :retire,
    'DataMigrations::DedupeTracksForUniqueIndexJob' => :retire,
    'DataMigrations::BackfillFamiliesForFamilyPlanJob' => :retire,
    'DataMigrations::BackfillFamilyMemberEntitlementsJob' => :retire,
    'DataMigrations::BackfillPlacesUserIdJob' => :a12_decoder,
    'DataMigrations::RecalculatePerTrackerTracksJob' => :a12,
    'DataMigrations::RecalculateAnomaliesJob' => :a12,
    'DataMigrations::BackfillAchievementsJob' => :a12,
    'DataMigrations::AddPointDimensionColumnsJob' => :a12,
    'DataMigrations::DropLegacyLatLonJob' => :a12,
    'TransportationModes::ImportBackfillJob' => :a7,
    'BulkStatsCalculatingJob' => :pre_floor_other_owner,
    'Import::UpdatePointsCountJob' => :pre_floor_other_owner,
    'Trips::CalculatePathJob' => :pre_floor_other_owner,
    'VisitSuggestingJob' => :pre_floor_other_owner
  }.freeze

  DELETED = %w[TransportationModes::BackfillJob].freeze

  CLASS = '([A-Z]\w*(?:::[A-Z]\w*)*Job)'
  CHAIN = /#{CLASS}\s*(?:\.set\([^)]*\)\s*)?\.perform_(?:later|now)/
  ENQUEUE = /#{CHAIN}|enqueue\(#{CLASS}\)|perform_all_later\(.*?#{CLASS}\.new/m

  def self.enqueued
    Dir[Rails.root.join('db/{migrate,data}/*.rb')].flat_map { File.read(_1).scan(ENQUEUE).flatten.compact }.uniq
  end

  def self.path(name) = Rails.root.join('app/jobs', "#{name.underscore}.rb")
end

RSpec.describe 'Wave 6 job inventory' do
  let(:classified) { Wave6Inventory::RELEASE.keys + Wave6Inventory::OTHER.keys }

  it 'gives every job a migration or data migration enqueues a disposition' do
    expect(Wave6Inventory.enqueued - classified - Wave6Inventory::DELETED).to be_empty
  end

  it 'lists as deleted only classes Rails no longer defines' do
    expect(Wave6Inventory::DELETED.map(&:safe_constantize)).to all(be_nil)
  end

  it 'keeps every classified class loadable until A12 deletes it' do
    classified.each { |name| expect(name.constantize).to be < ApplicationJob }
  end

  it 'recognises multi-line chains and perform_all_later' do
    source = <<~RUBY
      Foo::BarJob
        .set(wait: 1.minute)
        .perform_later
      ActiveJob.perform_all_later(ids.map { Baz::QuxJob.new(_1) })
    RUBY

    expect(source.scan(Wave6Inventory::ENQUEUE).flatten.compact).to eq(%w[Foo::BarJob Baz::QuxJob])
  end

  it 'maps every release class onto a release command type its file forwards' do
    expect(Wave6Inventory::RELEASE.values.uniq).to match_array(ReleaseCommands::COMMANDS.keys)

    Wave6Inventory::RELEASE.each do |name, type|
      expect(File.read(Wave6Inventory.path(name))).to include("'#{type}'"), name
    end
  end

  it 'routes no A12, A7 or retired class through a release command' do
    Wave6Inventory::OTHER.each_key do |name|
      expect(File.read(Wave6Inventory.path(name))).not_to include('ReleaseCommands'), name
    end
  end
end
