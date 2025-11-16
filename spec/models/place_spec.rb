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

    describe '#osm_id' do
      it 'returns the osm_id' do
        expect(place.osm_id).to eq(5_762_449_774)
      end
    end

    describe '#osm_key' do
      it 'returns the osm_key' do
        expect(place.osm_key).to eq('amenity')
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
        expect(place.lon).to be_within(0.000001).of(13.0948638)
      end
    end

    describe '#lat' do
      it 'returns the latitude' do
        expect(place.lat).to be_within(0.000001).of(54.2905245)
      end
    end
  end
end
