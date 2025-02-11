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
    it { is_expected.to validate_presence_of(:latitude) }
    it { is_expected.to validate_presence_of(:longitude) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:source).with_values(%i[manual photon]) }
  end

  describe 'methods' do
    describe '#async_reverse_geocode' do
      let(:place) { create(:place) }

      before { allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true) }

      it 'updates address' do
        expect { place.async_reverse_geocode }.to have_enqueued_job(ReverseGeocodingJob).with('Place', place.id)
      end
    end
  end
end
