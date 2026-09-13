# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::PlaceFinder do
  let(:user) { create(:user) }
  let(:visit_data) do
    {
      center_lat: 52.5126,
      center_lon: 13.4012,
      suggested_name: nil,
      points: [],
      start_time: Time.zone.now.to_i,
      end_time: (Time.zone.now + 1.hour).to_i,
      duration: 3600
    }
  end

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(DawarichSettings).to receive(:store_geodata?).and_return(false)
  end

  describe '#find_or_create_place' do
    it 'returns a Place (not a hash)' do
      result = described_class.new(user).find_or_create_place(visit_data)

      expect(result).to be_a(Place)
    end

    it 'creates exactly ONE place per call (no fan-out)' do
      expect { described_class.new(user).find_or_create_place(visit_data) }
        .to change { Place.count }.by(1)
    end

    it 'creates the place with Place::DEFAULT_NAME when no suggested_name is given' do
      result = described_class.new(user).find_or_create_place(visit_data)

      expect(result.name).to eq(Place::DEFAULT_NAME)
      expect(result.source).to eq('photon')
    end

    it 'uses suggested_name when present' do
      data = visit_data.merge(suggested_name: 'Home')

      expect(described_class.new(user).find_or_create_place(data).name).to eq('Home')
    end

    it 'reuses a same-name user place near the center' do
      existing = create(:place, user: user, name: Place::DEFAULT_NAME,
                                latitude: 52.5126, longitude: 13.4012)

      expect { described_class.new(user).find_or_create_place(visit_data) }
        .not_to have_enqueued_job(Places::NameFetchingJob)
      expect(described_class.new(user).find_or_create_place(visit_data)).to eq(existing)
    end

    it 'never persists geodata at creation (filled by Places::NameFetchingJob)' do
      result = described_class.new(user).find_or_create_place(visit_data)

      expect(result.geodata).to eq({})
    end

    it 'enqueues Places::NameFetchingJob for the new place when reverse geocoding is enabled' do
      expect { described_class.new(user).find_or_create_place(visit_data) }
        .to have_enqueued_job(Places::NameFetchingJob).with(an_instance_of(Integer))
    end

    it 'does not enqueue Places::NameFetchingJob when reverse geocoding is disabled' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)

      expect { described_class.new(user).find_or_create_place(visit_data) }
        .not_to have_enqueued_job(Places::NameFetchingJob)
    end
  end

  describe '#find_or_create_place candidate ranking' do
    def place_at(lat, lon, name:, source:)
      create(:place, user: user, name: name, source: source,
                     latitude: lat, longitude: lon, lonlat: "POINT(#{lon} #{lat})", geodata: {})
    end

    it 'does not merge a nearby place with a different name' do
      existing = place_at(52.5126, 13.4012, name: 'Different venue', source: :manual)

      result = described_class.new(user).find_or_create_place(visit_data.merge(suggested_name: 'Cafe'))

      expect(result).not_to eq(existing)
      expect(result.name).to eq('Cafe')
    end

    it 'prefers a normalized name match within the radius' do
      place_at(52.51262, 13.40122, name: 'Other', source: :photon)
      named = place_at(52.5126, 13.4012, name: ' cafe ', source: :photon)

      result = described_class.new(user).find_or_create_place(visit_data.merge(suggested_name: 'Cafe'))

      expect(result).to eq(named)
    end

    it 'reuses a stable external provider identifier before comparing names' do
      external = create(:place, user: user, name: 'Old provider name',
                                geodata: { 'external_place_id' => 'poi-42' })

      result = described_class.new(user).find_or_create_place(
        visit_data.merge(suggested_name: 'New provider name', external_place_id: 'poi-42')
      )

      expect(result).to eq(external)
    end

    it 'reuses a nearby place instead of minting a duplicate' do
      place_at(52.5126, 13.4012, name: 'Cafe', source: :photon)

      expect { described_class.new(user).find_or_create_place(visit_data.merge(suggested_name: 'Cafe')) }
        .not_to(change { Place.count })
    end
  end
end
