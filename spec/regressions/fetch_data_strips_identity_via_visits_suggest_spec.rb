# frozen_string_literal: true

require 'rails_helper'

# Closes the inferential gap between the unit-level reproducer and the production
# trip `import a favourite -> Visits::Suggest -> ReverseGeocodingJob('place', id)
# -> ReverseGeocoding::Places::FetchData#update_place` for an unlocked imported
# place. Before the fix this trip stripped `geodata['external_place_id']`,
# `geodata['semantic_type']`, flipped `source` from `:gpx_waypoint` to `:photon`,
# and renamed the row; the partial unique index `idx_places_user_external_place_id`
# could no longer defend the dedup-on-re-import contract that `PlaceWriter#upsert`
# depends on. After the fix the photon payload is merged in, identity keys are
# preserved, and `source` is left untouched for GPX-waypoint imports.
RSpec.describe 'ReverseGeocoding::Places::FetchData preserves import identity end-to-end ' \
               'via Visits::Suggest -> ReverseGeocodingJob -> FetchData' do
  include ActiveJob::TestHelper

  let!(:user) { create(:user) }
  let(:start_at) { Time.zone.local(2020, 1, 1, 0, 0, 0) }
  let(:end_at) { Time.zone.local(2020, 1, 1, 5, 0, 0) }

  let!(:imported_place) do
    create(:place,
           user: user,
           name: 'Cafe Riquet',
           latitude: 55.755826,
           longitude: 37.6173,
           source: :gpx_waypoint,
           geodata: { 'external_place_id' => 'gpx:abc123', 'semantic_type' => 'cafe' })
  end

  let(:photon_venue_result) do
    double(data: {
             'geometry' => { 'coordinates' => [37.6173, 55.755826] },
             'properties' => {
               'osm_key' => 'amenity',
               'osm_value' => 'cafe',
               'name' => 'Cafe Riquet',
               'city' => 'Moscow',
               'country' => 'Russia',
               'osm_id' => 999
             }
           })
  end

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
    allow(Geocoder).to receive(:search).and_return([photon_venue_result])
    create_visit_points(user, start_at)
    clear_enqueued_jobs
  end

  it 'attributes the stay to the imported place and preserves its identity through reverse geocoding' do
    expect { Visits::Suggest.new(user, start_at:, end_at:).call }.to change(Visit, :count).by(1)

    visit = Visit.last
    expect(visit.place_id).to eq(imported_place.id)

    reverse_geocoding_jobs = enqueued_jobs.select { |job| job['job_class'] == 'ReverseGeocodingJob' }
    expect(reverse_geocoding_jobs.count).to eq(1)
    expect(reverse_geocoding_jobs.first['arguments']).to include('place', imported_place.id)

    perform_enqueued_jobs(only: ReverseGeocodingJob)
    imported_place.reload

    # Photon refresh: name (unlocked import, expected behaviour) and city/country.
    expect(imported_place.name).to eq('Cafe Riquet (Cafe)')
    expect(imported_place.city).to eq('Moscow')
    expect(imported_place.country).to eq('Russia')
    expect(imported_place.reverse_geocoded_at).to be_present

    # Identity preserved: dedup key + import source provenance survive the run.
    expect(imported_place.geodata['external_place_id']).to eq('gpx:abc123')
    expect(imported_place.geodata['semantic_type']).to eq('cafe')
    expect(imported_place.source).to eq('gpx_waypoint')

    # Photon payload merged in alongside the preserved identity keys.
    expect(imported_place.geodata['properties']['osm_id']).to eq(999)
    expect(imported_place.geodata['properties']['name']).to eq('Cafe Riquet')
  end

  it 'still defends the dedup-on-re-import contract after a reverse-geocoding round' do
    Visits::Suggest.new(user, start_at:, end_at:).call
    perform_enqueued_jobs(only: ReverseGeocodingJob)

    writer = EnhancedImport::Writers::PlaceWriter.new(
      user, create(:import, user: user, source: :gpx, name: 'favourites.gpx'),
      source: :gpx_waypoint
    )
    extracted = EnhancedImport::Extracted::Place.new(
      external_place_id: 'gpx:abc123', name: 'Cafe Riquet',
      latitude: 55.755826, longitude: 37.6173, semantic_type: 'cafe', geodata_extras: {}
    )

    expect { writer.upsert(extracted) }.not_to(change { Place.where(user_id: user.id).count })
    expect(writer.upsert(extracted).first.id).to eq(imported_place.id)
  end

  private

  def create_visit_points(_user, start_time)
    12.times { |i| create(:point, :with_known_location, user:, timestamp: start_time + (i * 5).minutes) }
  end
end
