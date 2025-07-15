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

    describe '#trigger_track_processing' do
      let(:user) { create(:user) }
      let(:point) { build(:point, user: user) }

      context 'when point is from import' do
        let(:import) { create(:import, user: user) }
        let(:point) { build(:point, user: user, import: import) }

        it 'does not trigger track processing' do
          expect(TrackProcessingJob).not_to receive(:perform_now)
          expect(TrackProcessingJob).not_to receive(:perform_later)

          point.save!
        end
      end

      context 'when point is not from import' do
        context 'with no previous point' do
          it 'triggers immediate processing' do
            expect(TrackProcessingJob).to receive(:perform_now).with(user.id, 'incremental', point_id: point.id)

            point.save!
          end
        end

        context 'with previous point triggering immediate processing' do
          let!(:previous_point) { create(:point, user: user, timestamp: 2.hours.ago.to_i) }

          it 'triggers immediate processing' do
            expect(TrackProcessingJob).to receive(:perform_now).with(user.id, 'incremental', point_id: point.id)

            point.save!
          end
        end

        context 'with previous point not triggering immediate processing' do
          let!(:previous_point) { create(:point, user: user, timestamp: 10.minutes.ago.to_i, lonlat: 'POINT(13.404954 52.520008)') }
          let(:point) { build(:point, user: user, timestamp: 5.minutes.ago.to_i, lonlat: 'POINT(13.405954 52.521008)') }

          it 'triggers batched processing' do
            expect(TrackProcessingJob).to receive(:perform_later).with(user.id, 'incremental', point_id: point.id)

            point.save!
          end
        end
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

    describe '#should_trigger_immediate_processing?' do
      let(:user) { create(:user) }
      let(:point) { build(:point, user: user, timestamp: Time.current.to_i, lonlat: 'POINT(13.405954 52.521008)') }

      context 'with no previous point' do
        it 'returns true' do
          result = point.send(:should_trigger_immediate_processing?, nil)
          expect(result).to eq(true)
        end
      end

      context 'with previous point exceeding time threshold' do
        let(:previous_point) { create(:point, user: user, timestamp: 2.hours.ago.to_i, lonlat: 'POINT(13.404954 52.520008)') }

        it 'returns true' do
          result = point.send(:should_trigger_immediate_processing?, previous_point)
          expect(result).to eq(true)
        end
      end

      context 'with previous point exceeding distance threshold' do
        let(:previous_point) { create(:point, user: user, timestamp: 10.minutes.ago.to_i, lonlat: 'POINT(14.404954 53.520008)') }

        it 'returns true' do
          result = point.send(:should_trigger_immediate_processing?, previous_point)
          expect(result).to eq(true)
        end
      end

      context 'with previous point within both thresholds' do
        let(:previous_point) { create(:point, user: user, timestamp: 10.minutes.ago.to_i, lonlat: 'POINT(13.404954 52.520008)') }

        it 'returns false' do
          result = point.send(:should_trigger_immediate_processing?, previous_point)
          expect(result).to eq(false)
        end
      end

      context 'with previous point exactly at time threshold' do
        let(:previous_point) { create(:point, user: user, timestamp: 30.minutes.ago.to_i, lonlat: 'POINT(13.404954 52.520008)') }

        it 'returns false' do
          result = point.send(:should_trigger_immediate_processing?, previous_point)
          expect(result).to eq(false)
        end
      end

      context 'with previous point exactly at distance threshold' do
        let(:previous_point) { create(:point, user: user, timestamp: 10.minutes.ago.to_i, lonlat: 'POINT(13.404954 52.520008)') }

        before do
          # Mock distance calculation to return exactly 1.0 km
          allow(Geocoder::Calculations).to receive(:distance_between).and_return(1.0)
        end

        it 'returns false' do
          result = point.send(:should_trigger_immediate_processing?, previous_point)
          expect(result).to eq(false)
        end
      end
    end
  end
end
