# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Point, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:import).optional }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:country).optional }
    it { is_expected.to belong_to(:visit).optional }
    it { is_expected.to belong_to(:track).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:timestamp) }
    it { is_expected.to validate_presence_of(:lonlat) }
  end

  describe 'callbacks' do
    describe '#set_country' do
      let(:point) { build(:point, lonlat: 'POINT(-79.85581250721961 15.854775993302411)') }
      let(:country) { create(:country) }

      it 'sets the country' do
        expect(Country).to receive(:containing_point).with(-79.85581250721961, 15.854775993302411).and_return(country)

        point.save!

        expect(point.country_id).to eq(country.id)
      end
    end

    describe '#recalculate_track' do
      let(:point) { create(:point, track: track) }
      let(:track) { create(:track) }

      it 'recalculates the track' do
        expect(track).to receive(:recalculate_path_and_distance!)

        point.update(lonlat: 'POINT(-79.85581250721961 15.854775993302411)')
      end
    end
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

      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
        allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
      end

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

      context 'when reverse geocoding is disabled' do
        before do
          allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
        end

        it 'does not enqueue ReverseGeocodeJob' do
          expect { point.save }.not_to have_enqueued_job(ReverseGeocodingJob)
        end
      end
    end

    describe '#lon' do
      let(:point) { create(:point, lonlat: 'POINT(1 2)') }

      it 'returns longitude' do
        expect(point.lon).to eq(1)
      end
    end

    describe '#lat' do
      let(:point) { create(:point, lonlat: 'POINT(1 2)') }

      it 'returns latitude' do
        expect(point.lat).to eq(2)
      end
    end

    describe '#recalculate_track' do
      let(:point) { create(:point, track: track) }
      let(:track) { create(:track) }

      it 'recalculates the track' do
        expect(track).to receive(:recalculate_path_and_distance!)

        point.update(lonlat: 'POINT(-79.85581250721961 15.854775993302411)')
      end
    end

    describe '#trigger_incremental_track_generation' do
      let(:point) { create(:point, track: track) }
      let(:track) { create(:track) }

      it 'enqueues Tracks::IncrementalGeneratorJob' do
        expect { point.trigger_incremental_track_generation }.to have_enqueued_job(Tracks::IncrementalGeneratorJob)
      end
    end
  end
end
