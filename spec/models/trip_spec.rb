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
        expect(Trips::CalculateAllJob).to receive(:perform_later)

        trip.save
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
          orientation: 'portrait'
        },
        {
          id: '789',
          url: "/api/v1/photos/789/thumbnail.jpg?api_key=#{user.api_key}&source=immich",
          source: 'immich',
          orientation: 'portrait'
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
  end
end
