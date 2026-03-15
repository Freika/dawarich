# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Tracks, type: :service do
  let(:user) { create(:user) }

  describe '#call' do
    context 'when tracks_data is not an array' do
      it 'returns 0 for nil' do
        service = described_class.new(user, nil)
        expect(service.call).to eq(0)
      end

      it 'returns 0 for a hash' do
        service = described_class.new(user, { 'start_at' => '2024-01-01' })
        expect(service.call).to eq(0)
      end
    end

    context 'when tracks_data is empty' do
      it 'returns 0' do
        service = described_class.new(user, [])
        expect(service.call).to eq(0)
      end
    end

    context 'with valid tracks data' do
      let(:tracks_data) do
        [
          {
            'start_at' => '2024-01-15T08:00:00Z',
            'end_at' => '2024-01-15T09:00:00Z',
            'original_path' => 'LINESTRING(-74.006 40.7128, -74.007 40.713)',
            'distance' => 1500,
            'avg_speed' => 25.0,
            'duration' => 3600,
            'elevation_gain' => 50,
            'elevation_loss' => 20,
            'elevation_max' => 100,
            'elevation_min' => 50,
            'dominant_mode' => 5,
            'segments' => [
              {
                'transportation_mode' => 'driving',
                'start_index' => 0,
                'end_index' => 10,
                'distance' => 1500,
                'duration' => 3600,
                'avg_speed' => 25.0,
                'max_speed' => 50.0,
                'confidence' => 'medium',
                'source' => 'inferred'
              }
            ]
          }
        ]
      end

      it 'creates the track' do
        service = described_class.new(user, tracks_data)

        expect { service.call }.to change { user.tracks.count }.by(1)
      end

      it 'returns the count of created tracks' do
        service = described_class.new(user, tracks_data)

        expect(service.call).to eq(1)
      end

      it 'sets the correct attributes' do
        service = described_class.new(user, tracks_data)
        service.call

        track = user.tracks.first
        expect(track.distance).to eq(1500)
        expect(track.avg_speed).to eq(25.0)
        expect(track.duration).to eq(3600)
        expect(track.original_path).to be_present
      end

      it 'creates track segments' do
        service = described_class.new(user, tracks_data)
        service.call

        track = user.tracks.first
        expect(track.track_segments.count).to eq(1)

        segment = track.track_segments.first
        expect(segment.transportation_mode).to eq('driving')
        expect(segment.start_index).to eq(0)
        expect(segment.end_index).to eq(10)
      end
    end

    context 'with duplicate tracks' do
      let(:tracks_data) do
        [
          {
            'start_at' => '2024-01-15T08:00:00Z',
            'end_at' => '2024-01-15T09:00:00Z',
            'original_path' => 'LINESTRING(-74.006 40.7128, -74.007 40.713)',
            'distance' => 1500,
            'avg_speed' => 25.0,
            'duration' => 3600
          }
        ]
      end

      let!(:existing_track) do
        create(:track,
               user: user,
               start_at: Time.zone.parse('2024-01-15T08:00:00Z'),
               end_at: Time.zone.parse('2024-01-15T09:00:00Z'),
               distance: 1500)
      end

      it 'skips the duplicate track' do
        service = described_class.new(user, tracks_data)

        expect { service.call }.not_to(change { user.tracks.count })
      end

      it 'returns 0 for skipped tracks' do
        service = described_class.new(user, tracks_data)

        expect(service.call).to eq(0)
      end
    end

    context 'with tracks without segments' do
      let(:tracks_data) do
        [
          {
            'start_at' => '2024-01-15T08:00:00Z',
            'end_at' => '2024-01-15T09:00:00Z',
            'original_path' => 'LINESTRING(-74.006 40.7128, -74.007 40.713)',
            'distance' => 1500,
            'avg_speed' => 25.0,
            'duration' => 3600
          }
        ]
      end

      it 'creates the track without segments' do
        service = described_class.new(user, tracks_data)
        service.call

        track = user.tracks.first
        expect(track).to be_present
        expect(track.track_segments.count).to eq(0)
      end
    end
  end
end
