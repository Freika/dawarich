# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trip, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:started_at) }
    it { is_expected.to validate_presence_of(:ended_at) }

    context 'date range validation' do
      let(:user) { create(:user) }

      it 'is valid when started_at is before ended_at' do
        trip = build(:trip, user: user, started_at: 1.day.ago, ended_at: Time.current)
        expect(trip).to be_valid
      end

      it 'is invalid when started_at is after ended_at' do
        trip = build(:trip, user: user, started_at: Time.current, ended_at: 1.day.ago)
        expect(trip).not_to be_valid
        expect(trip.errors[:ended_at]).to include('must be after start date')
      end

      it 'is invalid when started_at equals ended_at' do
        time = Time.current
        trip = build(:trip, user: user, started_at: time, ended_at: time)
        expect(trip).not_to be_valid
        expect(trip.errors[:ended_at]).to include('must be after start date')
      end

      it 'is valid when both dates are blank during initialization' do
        trip = Trip.new(user: user, name: 'Test Trip')
        expect(trip.errors[:ended_at]).to be_empty
      end
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'callbacks' do
    let(:user) { create(:user) }
    let(:trip) { create(:trip, :with_points, user:) }

    context 'when the trip is created' do
      let(:trip) { build(:trip, :with_points, user:) }

      it 'enqueues the calculation jobs' do
        expect { trip.save }.to have_enqueued_job(Trips::CalculateAllJob)
      end
    end
  end

  describe '#photo_previews' do
    let(:photo_data) do
      [
        {
          'id' => '123',
          'latitude' => 35.6762,
          'longitude' => 139.6503,
          'localDateTime' => '2024-01-01T03:00:00.000Z',
          'type' => 'photo',
          'exifInfo' => {
            'orientation' => '3'
          }
        },
        {
          'id' => '456',
          'latitude' => 40.7128,
          'longitude' => -74.0060,
          'localDateTime' => '2024-01-02T01:00:00.000Z',
          'type' => 'photo',
          'exifInfo' => {
            'orientation' => '6'
          }
        },
        {
          'id' => '789',
          'latitude' => 40.7128,
          'longitude' => -74.0060,
          'localDateTime' => '2024-01-02T02:00:00.000Z',
          'type' => 'photo',
          'exifInfo' => {
            'orientation' => '6'
          }
        }
      ]
    end
    let(:user) { create(:user, settings: settings) }
    let(:trip) { create(:trip, user:) }
    let(:expected_photos) do
      [
        {
          id: '456',
          url: "/api/v1/photos/456/thumbnail.jpg?api_key=#{user.api_key}&source=immich",
          source: 'immich',
          orientation: 'portrait',
          taken_at: '2024-01-02T01:00:00.000Z'
        },
        {
          id: '789',
          url: "/api/v1/photos/789/thumbnail.jpg?api_key=#{user.api_key}&source=immich",
          source: 'immich',
          orientation: 'portrait',
          taken_at: '2024-01-02T02:00:00.000Z'
        }
      ]
    end

    before do
      allow_any_instance_of(Immich::RequestPhotos).to receive(:call).and_return(photo_data)
    end

    context 'when Immich integration is not configured' do
      let(:settings) { {} }

      it 'returns an empty array' do
        expect(trip.photo_previews).to eq([])
      end
    end

    context 'when Immich integration is configured' do
      let(:settings) do
        {
          immich_url: 'https://immich.example.com',
          immich_api_key: '1234567890'
        }
      end

      it 'returns the photos' do
        expect(trip.photo_previews).to include(expected_photos[0])
        expect(trip.photo_previews).to include(expected_photos[1])
        expect(trip.photo_previews.size).to eq(2)
      end
    end
  end

  describe '#photos_by_day' do
    let(:user) { create(:user) }
    let(:trip) { create(:trip, user: user) }

    context 'when there are photos with timestamps' do
      let(:photos) do
        [
          { id: 1, url: '/p/1', source: 'immich', orientation: 'landscape', taken_at: '2024-11-27T23:30:00Z' },
          { id: 2, url: '/p/2', source: 'immich', orientation: 'landscape', taken_at: '2024-11-29T08:00:00Z' },
          { id: 3, url: '/p/3', source: 'immich', orientation: 'landscape', taken_at: nil }
        ]
      end

      before do
        allow(Trips::Photos).to receive(:new).with(trip, user)
                                             .and_return(instance_double(Trips::Photos, call: photos))
      end

      it 'buckets a photo by its UTC instant converted into the given timezone, not its UTC date' do
        result = trip.photos_by_day('Europe/Berlin')

        expect(result.keys).to contain_exactly(Date.new(2024, 11, 28), Date.new(2024, 11, 29))
        expect(result[Date.new(2024, 11, 28)].map { _1[:id] }).to eq([1])
        expect(result[Date.new(2024, 11, 29)].map { _1[:id] }).to eq([2])
      end

      it 'excludes photos with a blank taken_at' do
        result = trip.photos_by_day('Europe/Berlin')

        expect(result.values.flatten.map { _1[:id] }).not_to include(3)
      end
    end

    context 'when a photo has a naive (no-offset) timestamp' do
      let(:photos) do
        [{ id: 9, url: '/p/9', source: 'immich', orientation: 'landscape', taken_at: '2024-11-30T00:30:00' }]
      end

      before do
        allow(Trips::Photos).to receive(:new).with(trip, user)
                                             .and_return(instance_double(Trips::Photos, call: photos))
      end

      it 'buckets it as wall-clock time in the given timezone' do
        result = trip.photos_by_day('Europe/Berlin')

        expect(result.keys).to contain_exactly(Date.new(2024, 11, 30))
        expect(result[Date.new(2024, 11, 30)].map { _1[:id] }).to eq([9])
      end
    end

    context 'when there are no photos' do
      before do
        allow(Trips::Photos).to receive(:new).with(trip, user)
                                             .and_return(instance_double(Trips::Photos, call: []))
      end

      it 'returns an empty hash' do
        expect(trip.photos_by_day('Europe/Berlin')).to eq({})
      end
    end
  end

  describe 'Calculateable concern' do
    let(:user) { create(:user) }
    let(:trip) { create(:trip, user: user) }
    let!(:points) do
      [
        create(:point, user: user, lonlat: 'POINT(13.404954 52.520008)', timestamp: trip.started_at.to_i + 1.hour),
        create(:point, user: user, lonlat: 'POINT(13.404955 52.520009)', timestamp: trip.started_at.to_i + 2.hours),
        create(:point, user: user, lonlat: 'POINT(13.404956 52.520010)', timestamp: trip.started_at.to_i + 3.hours)
      ]
    end

    describe '#calculate_distance' do
      it 'stores distance in user preferred unit for Trip model' do
        allow(user).to receive(:safe_settings).and_return(double(distance_unit: 'km'))
        allow(Point).to receive(:total_distance).and_return(2.5) # 2.5 km

        trip.calculate_distance

        expect(trip.distance).to eq(3) # Should be rounded, in km
      end
    end

    describe '#recalculate_distance!' do
      it 'recalculates and saves the distance' do
        original_distance = trip.distance

        trip.recalculate_distance!

        trip.reload
        expect(trip.distance).not_to eq(original_distance)
      end
    end

    describe '#recalculate_path!' do
      it 'recalculates and saves the path' do
        original_path = trip.path

        trip.recalculate_path!

        trip.reload
        expect(trip.path).not_to eq(original_path)
      end
    end

    describe '#calculate_path' do
      context 'when trip has no points' do
        let(:empty_user) { create(:user) }
        let(:empty_trip) do
          create(:trip, user: empty_user,
                        started_at: 1.year.ago,
                        ended_at: 1.year.ago + 1.day)
        end

        it 'sets path to nil without raising' do
          expect { empty_trip.calculate_path }.not_to raise_error
          expect(empty_trip.path).to be_nil
        end
      end

      context 'when trip has only one point' do
        let(:single_user) { create(:user) }
        let(:single_trip) do
          create(:trip, user: single_user,
                        started_at: 2.years.ago,
                        ended_at: 2.years.ago + 1.day)
        end

        before do
          create(:point, user: single_user,
                         lonlat: 'POINT(10.0 50.0)',
                         timestamp: single_trip.started_at.to_i + 3600)
        end

        it 'sets path to nil without raising' do
          expect { single_trip.calculate_path }.not_to raise_error
          expect(single_trip.path).to be_nil
        end
      end
    end
  end
end
