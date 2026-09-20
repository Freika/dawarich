# frozen_string_literal: true

require 'rails_helper'

# Dedup for re-imported favourites reads geodata->>'external_place_id'. Four other
# geodata writers drop their payload when the instance opts out of storing geodata;
# this writer must not, or every watcher re-import would duplicate every favourite.
RSpec.describe 'Extracted place identity survives an instance opting out of geodata' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :gpx, name: 'favourites.gpx') }
  let(:writer) { EnhancedImport::Writers::PlaceWriter.new(user, import) }

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

  before { allow(DawarichSettings).to receive(:store_geodata?).and_return(false) }

  it 'still writes the identity used for dedup' do
    place, = writer.upsert(extracted)

    expect(place.geodata['external_place_id']).to eq('gpx:abc123')
  end

  it 'reuses the existing place on a second run instead of duplicating it' do
    writer.upsert(extracted)

    expect { writer.upsert(extracted) }.not_to(change { Place.where(user_id: user.id).count })
  end
end
