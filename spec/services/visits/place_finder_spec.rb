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

    it 'reuses an existing user place near the center' do
      existing = create(:place, user: user, latitude: 52.5126, longitude: 13.4012)

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

    it 'prefers a manual place over a photon place at the same location' do
      photon = place_at(52.5126, 13.4012, name: 'Photon', source: :photon)
      manual = place_at(52.5126, 13.4012, name: 'Manual', source: :manual)

      result = described_class.new(user).find_or_create_place(visit_data)

      expect(result).to eq(manual)
      expect(result).not_to eq(photon)
    end

    it 'prefers an exact name match within the radius' do
      place_at(52.51262, 13.40122, name: 'Other', source: :photon)
      named = place_at(52.5126, 13.4012, name: 'Cafe', source: :photon)

      result = described_class.new(user).find_or_create_place(visit_data.merge(suggested_name: 'Cafe'))

      expect(result).to eq(named)
    end

    it 'reuses a nearby place instead of minting a duplicate' do
      place_at(52.5126, 13.4012, name: 'Cafe', source: :photon)

      expect { described_class.new(user).find_or_create_place(visit_data.merge(suggested_name: 'Cafe')) }
        .not_to(change { Place.count })
    end
  end
end
