# frozen_string_literal: true

require 'rails_helper'

# Regression for the silent strip introduced alongside GPX-waypoint importing
# (commit bdfb4c2): `ReverseGeocoding::Places::FetchData#update_place`
# wholesale-replaced the `geodata` jsonb column with the Photon payload and
# flipped `source` back to `:photon`, erasing the `external_place_id` /
# `semantic_type` identity keys the enhanced-import `PlaceWriter` wrote and
# `find_by_external_id` depends on. The fix merges the Photon payload into
# the existing `geodata`, honours `DawarichSettings.store_geodata?` like the
# reverse-geocoding peers, and stops rewriting `source` for `gpx_waypoint`
# imports.
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

    it 'preserves the identity keys, writes no Photon payload, and still dedups on re-import' do
      place, = writer.upsert(extracted)
      fetch_data(place.id)
      place.reload

      expect(place.geodata).to eq('external_place_id' => 'gpx:abc123', 'semantic_type' => 'Food')
      expect(place.geodata['properties']).to be_nil
      expect(place.source).to eq('gpx_waypoint')

      expect { writer.upsert(extracted) }.not_to(change { Place.where(user_id: user.id).count })
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
