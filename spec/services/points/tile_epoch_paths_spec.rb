# frozen_string_literal: true

require 'rails_helper'

# Every path that writes or deletes points must invalidate the tile epoch,
# or cached vector tiles 304 forever against changed data.
RSpec.describe 'Points::TileEpoch write-path integration' do
  let(:user) { create(:user) }
  let(:timestamp) { Time.utc(2024, 6, 1, 12, 0, 0).to_i }

  def current_component
    Points::TileEpoch.etag_component(
      user.id, Time.utc(2024, 1, 1).to_i, Time.utc(2024, 12, 31).to_i
    )
  end

  def expect_bump
    before_value = current_component
    yield
    expect(current_component).not_to eq(before_value)
  end

  # For paths whose fixture timestamps span arbitrary years
  def all_time_component
    Points::TileEpoch.etag_component(user.id, 0, Time.utc(2100, 1, 1).to_i)
  end

  def expect_bump_all_time
    before_value = all_time_component
    yield
    expect(all_time_component).not_to eq(before_value)
  end

  it 'bumps from the archival_safe_upsert_all choke point (all bulk creators funnel through it)' do
    expect_bump do
      Point.archival_safe_upsert_all(
        [{ user_id: user.id, timestamp: timestamp, lonlat: 'POINT(13.4 52.5)' }],
        returning: Arel.sql('id')
      )
    end
  end

  it 'bumps when points are created through Points::Create' do
    params = { locations: [
      { type: 'Feature',
        geometry: { type: 'Point', coordinates: [13.4, 52.5] },
        properties: { timestamp: Time.zone.at(timestamp).iso8601, altitude: 5, speed: 1 } }
    ] }

    expect_bump { Points::Create.new(user, params).call }
  end

  it 'bumps when points are destroyed through Points::Destroyer' do
    point = create(:point, user:, timestamp: timestamp)

    expect_bump { Points::Destroyer.new(user, point.id).call }
  end

  it 'bumps when points arrive through Users::ImportData::Points' do
    points_data = [
      { 'timestamp' => timestamp, 'longitude' => 13.4, 'latitude' => 52.5,
        'lonlat' => 'POINT(13.4 52.5)' }
    ]

    expect_bump { Users::ImportData::Points.new(user, points_data).call }
  end

  it 'bumps when points arrive through an Imports::BulkInsertable importer' do
    import = create(:import, user:, name: 'geojson.json', source: :geojson)
    file_path = Rails.root.join('spec/fixtures/files/geojson/export.json').to_s

    expect_bump_all_time { Geojson::Importer.new(import, user.id, file_path).call }
  end

  it 'bumps when points arrive through GoogleMaps::SemanticHistoryImporter (bypasses both choke points)' do
    import = create(:import, user:, name: 'semantic.json', source: :google_semantic_history)
    file_path = Rails.root.join(
      'spec/fixtures/files/google/location-history/with_activitySegment_with_startLocation.json'
    ).to_s

    expect_bump_all_time { GoogleMaps::SemanticHistoryImporter.new(import, user.id, file_path).call }
  end

  it 'bumps the window years when Points::AnomalyFilter flags points' do
    create(:point, user:, timestamp: timestamp, lonlat: 'POINT(0 0)',
                   longitude: 0.0, latitude: 0.0)

    expect_bump do
      Points::AnomalyFilter.new(user.id, timestamp - 3600, timestamp + 3600).call
    end
  end

  it 'bumps when DataMigrations::CleanupNullIslandJob flags null-island points' do
    create(:point, user:, timestamp: timestamp, lonlat: 'POINT(0 0)',
                   longitude: 0.0, latitude: 0.0)

    expect_bump { DataMigrations::CleanupNullIslandJob.new.perform(user.id) }
  end

  it 'bumps when an import and its points are destroyed through Imports::Destroy' do
    import = create(:import, user:)
    create(:point, user:, import:, timestamp: timestamp)

    expect_bump { Imports::Destroy.new(user, import).call }
  end
end
