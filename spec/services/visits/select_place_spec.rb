# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::SelectPlace do
  let(:user)  { create(:user) }
  let(:visit) { create(:visit, user: user, area: nil, place: nil) }

  let(:photon_payload) do
    {
      name: 'Café Bravo',
      latitude: 52.5126,
      longitude: 13.4012,
      osm_id: 1_234_567,
      osm_type: 'N',
      osm_key: 'amenity',
      osm_value: 'cafe',
      city: 'Berlin',
      country: 'Germany',
      geodata: { 'properties' => { 'osm_id' => 1_234_567, 'name' => 'Café Bravo' } }
    }
  end

  before do
    allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
  end

  describe '#call' do
    it 'creates a user-scoped Place when no match exists' do
      place = described_class.new(user: user, visit: visit, photon: photon_payload).call

      expect(place).to be_persisted
      expect(place.user).to eq(user)
      expect(place.name).to eq('Café Bravo')
      expect(place.source).to eq('photon')
      expect(visit.reload.place_id).to eq(place.id)
      expect(visit.name).to eq('Café Bravo')
    end

    it 'locks the name of a place the user picked so reverse geocoding cannot rewrite it' do
      place = described_class.new(user: user, visit: visit, photon: photon_payload).call

      expect(place.reload).to be_name_locked
    end

    it 'locks the name of an existing place the user picked' do
      existing = create(:place, user: user, name: photon_payload[:name],
                                latitude: photon_payload[:latitude], longitude: photon_payload[:longitude])

      described_class.new(user: user, visit: visit, photon: photon_payload.except(:osm_id, :geodata)).call

      expect(existing.reload).to be_name_locked
    end

    it 'does not match another user\'s place at the same name and coords (isolation)' do
      other = create(:user)
      create(:place, user: other, name: 'Café Bravo', latitude: 52.5126, longitude: 13.4012)

      place = described_class.new(user: user, visit: visit, photon: photon_payload).call

      expect(place.user).to eq(user)
      expect(user.places.count).to eq(1)
    end

    it 'reuses an existing place matched by name + 50m proximity' do
      existing = create(:place, user: user, name: 'Café Bravo', latitude: 52.5126, longitude: 13.4012)

      place = described_class.new(user: user, visit: visit, photon: photon_payload.except(:osm_id, :geodata)).call

      expect(place.id).to eq(existing.id)
      expect(user.places.count).to eq(1)
    end

    it 'is idempotent across repeated calls' do
      first  = described_class.new(user: user, visit: visit, photon: photon_payload).call
      second = described_class.new(user: user, visit: visit, photon: photon_payload).call

      expect(first.id).to eq(second.id)
      expect(user.places.count).to eq(1)
    end

    it 'does not persist geodata when store_geodata? is disabled' do
      allow(DawarichSettings).to receive(:store_geodata?).and_return(false)

      place = described_class.new(user: user, visit: visit, photon: photon_payload).call

      expect(place.geodata).to eq({})
    end
  end
end
