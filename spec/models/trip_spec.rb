# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trip, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:started_at) }
    it { is_expected.to validate_presence_of(:ended_at) }
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

    context 'when DawarichSettings.store_geodata? is enabled' do
      before do
        allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
      end

      it 'sets the countries' do
        expect(trip.countries).to eq(trip.points.pluck(:country).uniq.compact)
      end
    end
  end

  describe '#countries' do
    let(:user) { create(:user) }
    let(:trip) { create(:trip, user:) }
    let(:points) do
      create_list(
        :point,
        25,
        :reverse_geocoded,
        user:,
        timestamp: (trip.started_at.to_i..trip.ended_at.to_i).to_a.sample
      )
    end

    it 'returns the unique countries of the points' do
      expect(trip.countries).to eq(trip.points.pluck(:country).uniq.compact)
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
end
