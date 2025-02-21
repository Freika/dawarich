# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Point, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:import).optional }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:timestamp) }
    it { is_expected.to validate_presence_of(:lonlat) }
  end

  describe 'scopes' do
    describe '.reverse_geocoded' do
      let(:point) { create(:point, :reverse_geocoded) }
      let(:point_without_address) { create(:point, city: nil, country: nil) }

      it 'returns points with reverse geocoded address' do
        expect(described_class.reverse_geocoded).to eq([point])
      end
    end

    describe '.not_reverse_geocoded' do
      let(:point) { create(:point, country: 'Country', city: 'City') }
      let(:point_without_address) { create(:point, city: nil, country: nil) }

      it 'returns points without reverse geocoded address' do
        expect(described_class.not_reverse_geocoded).to eq([point_without_address])
      end
    end
  end

  describe 'methods' do
    describe '#recorded_at' do
      let(:point) { create(:point, timestamp: 1_554_317_696) }

      it 'returns recorded at time' do
        expect(point.recorded_at).to eq(Time.zone.at(1_554_317_696))
      end
    end

    describe '#async_reverse_geocode' do
      let(:point) { build(:point) }

      before { allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true) }

      it 'enqueues ReverseGeocodeJob with correct arguments' do
        point.save

        expect { point.async_reverse_geocode }.to have_enqueued_job(ReverseGeocodingJob)
          .with('Point', point.id)
      end

      context 'when point is imported' do
        let(:point) { build(:point, import_id: 1) }

        it 'enqueues ReverseGeocodeJob' do
          expect { point.async_reverse_geocode }.to have_enqueued_job(ReverseGeocodingJob)
        end
      end
    end
  end
end
