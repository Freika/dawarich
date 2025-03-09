# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Place, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:visits).dependent(:destroy) }
    it { is_expected.to have_many(:place_visits).dependent(:destroy) }
    it { is_expected.to have_many(:suggested_visits).through(:place_visits) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:lonlat) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:source).with_values(%i[manual photon]) }
  end

  describe 'methods' do
    let(:place) { create(:place, :with_geodata) }

    describe '#async_reverse_geocode' do
      before { allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true) }
      before { allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true) }

      it 'updates address' do
        expect { place.async_reverse_geocode }.to have_enqueued_job(ReverseGeocodingJob).with('Place', place.id)
      end
    end

    describe '#osm_id' do
      it 'returns the osm_id' do
        expect(place.osm_id).to eq(583_204_619)
      end
    end

    describe '#osm_key' do
      it 'returns the osm_key' do
        expect(place.osm_key).to eq('tourism')
      end
    end

    describe '#osm_value' do
      it 'returns the osm_value' do
        expect(place.osm_value).to eq('restaurant')
      end
    end

    describe '#osm_type' do
      it 'returns the osm_type' do
        expect(place.osm_type).to eq('N')
      end
    end

    describe '#lon' do
      it 'returns the longitude' do
        expect(place.lon).to eq(13.094891305125158)
      end
    end

    describe '#lat' do
      it 'returns the latitude' do
        expect(place.lat).to eq(54.29058712007127)
      end
    end
  end
end
