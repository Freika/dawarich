# frozen_string_literal: true

require 'rails_helper'

# Regression for the silent strip introduced alongside GPX-waypoint importing
# (commit bdfb4c2): `ReverseGeocoding::Places::FetchData#update_place`
# wholesale-replaced the `geodata` jsonb column with the Photon payload and
# flipped `source` back to `:photon`, erasing the `external_place_id` /
# `semantic_type` identity keys the enhanced-import `PlaceWriter` wrote and
# `find_by_external_id` depends on. The fix merges the Photon payload into
# the existing `geodata` and stops rewriting `source` for `gpx_waypoint`
# imports, on both the primary and the sibling (bulk) update paths. It also
# brings this writer in line with its peers on `store_geodata?`: on an opt-out
# instance only the import identity and the four osm properties the app itself
# looks up are kept, not the whole provider payload.
RSpec.describe 'ReverseGeocoding::Places::FetchData preserves import identity' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :gpx, name: 'favourites.gpx') }
  let(:writer) { EnhancedImport::Writers::PlaceWriter.new(user, import, source: :gpx_waypoint) }
  let(:photon_venue_result) do
    double(data: {
             'geometry' => { 'coordinates' => [12.3750, 51.3369] },
             'properties' => {
               'osm_id' => 999_999,
               'name' => 'Cafe Riquet',
               'osm_value' => 'cafe',
               'osm_key' => 'amenity',
               'city' => 'Leipzig',
               'country' => 'Germany'
             }
           })
  end
  let(:street_result) do
    double(data: {
             'geometry' => { 'coordinates' => [12.3760, 51.3372] },
             'properties' => {
               'osm_id' => 111_111,
               'name' => nil,
               'street' => 'Schuhmachergäßchen',
               'osm_value' => 'residential',
               'osm_key' => 'highway',
               'city' => 'Leipzig',
               'country' => 'Germany'
             }
           })
  end
  let(:extracted) do
    EnhancedImport::Extracted::Place.new(
      external_place_id: 'gpx:abc123',
      name: 'Cafe Riquet',
      latitude: 51.3369,
      longitude: 12.3750,
      semantic_type: 'Food',
      geodata_extras: {}
    )
  end

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
    allow(Geocoding::Search).to receive(:call).and_return([photon_venue_result])
  end

  def fetch_data(place_id)
    ReverseGeocoding::Places::FetchData.new(place_id).call
  end

  it 'preserves external_place_id, semantic_type, and gpx_waypoint source while merging the Photon payload' do
    place, = writer.upsert(extracted)
    fetch_data(place.id)
    place.reload

    expect(place.geodata['external_place_id']).to eq('gpx:abc123')
    expect(place.geodata['semantic_type']).to eq('Food')
    expect(place.source).to eq('gpx_waypoint')
    expect(place.geodata['properties']['osm_id']).to eq(999_999)
  end

  it 'still renames an unlocked imported place from the Photon result' do
    place, = writer.upsert(extracted)
    fetch_data(place.id)
    place.reload

    expect(place.name).to eq('Cafe Riquet (Cafe)')
    expect(place.city).to eq('Leipzig')
    expect(place.country).to eq('Germany')
    expect(place.reverse_geocoded_at).to be_present
  end

  it 'preserves identity when the imported place is name-locked (merge runs outside the name_locked? guard)' do
    place, = writer.upsert(extracted)
    place.update!(name: 'My Cafe', user_named: true, name_locked_at: 1.hour.ago)

    fetch_data(place.id)
    place.reload

    expect(place.name).to eq('My Cafe')
    expect(place.source).to eq('gpx_waypoint')
    expect(place.geodata['external_place_id']).to eq('gpx:abc123')
    expect(place.geodata['semantic_type']).to eq('Food')
  end

  it 're-importing the same POI favourite after reverse geocoding does not mint a duplicate' do
    place, = writer.upsert(extracted)
    fetch_data(place.id)

    expect { writer.upsert(extracted) }.not_to(change { Place.where(user_id: user.id).count })
  end

  context 'when the instance opted out of storing geodata' do
    before { allow(DawarichSettings).to receive(:store_geodata?).and_return(false) }

    it 'keeps the import identity and still dedups the re-imported favourite' do
      place, = writer.upsert(extracted)
      fetch_data(place.id)
      place.reload

      expect(place.geodata['external_place_id']).to eq('gpx:abc123')
      expect(place.geodata['semantic_type']).to eq('Food')
      expect(place.source).to eq('gpx_waypoint')

      expect { writer.upsert(extracted) }.not_to(change { Place.where(user_id: user.id).count })
    end

    it 'keeps only the osm properties the app looks up, not the rest of the payload' do
      place, = writer.upsert(extracted)
      fetch_data(place.id)
      place.reload

      expect(place.geodata['properties']).to eq(
        'osm_id' => 999_999, 'osm_key' => 'amenity', 'osm_value' => 'cafe'
      )
      expect(place.geodata).not_to have_key('geometry')
      # The display fields live in their own columns, so nothing is lost.
      expect(place.city).to eq('Leipzig')
      expect(place.country).to eq('Germany')
    end

    it 'keeps the sibling path reduced too' do
      imported, = writer.upsert(extracted)
      fetch_data(imported.id)

      neighbour = create(:place, user: user, latitude: 51.3372, longitude: 12.3760, source: :photon)
      allow(Geocoding::Search).to receive(:call).and_return([street_result, photon_venue_result])

      fetch_data(neighbour.id)

      expect(neighbour.reload.geodata['properties'].keys)
        .to match_array(%w[osm_id osm_key osm_value])
    end
  end

  context 'when the imported place comes back as a sibling of another place' do
    it 'keeps identity and source through the bulk sibling update' do
      imported, = writer.upsert(extracted)
      fetch_data(imported.id)

      neighbour = create(:place, user: user, latitude: 51.3372, longitude: 12.3760, source: :photon)
      allow(Geocoding::Search).to receive(:call).and_return([street_result, photon_venue_result])

      fetch_data(neighbour.id)
      imported.reload

      expect(imported.geodata['external_place_id']).to eq('gpx:abc123')
      expect(imported.geodata['semantic_type']).to eq('Food')
      expect(imported.geodata['properties']['osm_id']).to eq(999_999)
      expect(imported.source).to eq('gpx_waypoint')
      expect(Place.where(user_id: user.id).count).to eq(2)
    end
  end

  context 'when a Google/Polarsteps import is stamped source = photon' do
    it 'preserves identity without a photon-to-photon source-flip regression' do
      place = create(:place,
                     user: user,
                     name: 'Cafe Riquet',
                     latitude: 51.3369,
                     longitude: 12.3750,
                     source: :photon,
                     geodata: { 'external_place_id' => 'google:place-42',
                                'semantic_type' => 'cafe' })

      fetch_data(place.id)
      place.reload

      expect(place.geodata['external_place_id']).to eq('google:place-42')
      expect(place.geodata['semantic_type']).to eq('cafe')
      expect(place.source).to eq('photon')
    end
  end
end
