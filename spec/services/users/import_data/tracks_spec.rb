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

    context 'when a concurrent insert wins the (start_at, end_at) race' do
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

      it 'rescues RecordNotUnique and continues without raising' do
        service = described_class.new(user, tracks_data)

        allow(user.tracks).to receive(:find_by).and_return(nil)
        allow(user.tracks).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new('uniq'))

        expect { service.call }.not_to raise_error
        expect(service.call).to eq(0)
      end
    end

    context 'when import data tries to override sensitive attributes' do
      let(:other_user) { create(:user) }
      let(:start_at) { Time.zone.parse('2024-02-01T08:00:00Z') }
      let(:end_at) { Time.zone.parse('2024-02-01T09:00:00Z') }
      let(:malicious_data) do
        [
          {
            'user_id' => other_user.id,
            'id' => 999_999,
            'created_at' => '2000-01-01T00:00:00Z',
            'updated_at' => '2000-01-01T00:00:00Z',
            'start_at' => start_at,
            'end_at' => end_at,
            'original_path' => 'LINESTRING(-74.006 40.7128, -74.007 40.713)',
            'distance' => 1500,
            'avg_speed' => 25.0,
            'duration' => 3600
          }
        ]
      end

      it 'ignores user_id, id, and timestamp attributes on create' do
        described_class.new(user, malicious_data).call

        track = user.tracks.find_by(start_at: start_at)
        expect(track).to be_present
        expect(track.user_id).to eq(user.id)
        expect(track.id).not_to eq(999_999)
        expect(track.created_at).to be > 1.year.ago
      end

      it 'ignores user_id and id attributes when refreshing on RecordNotUnique race' do
        existing = create(:track, user: user, start_at: start_at, end_at: end_at, distance: 100)

        described_class.new(user, malicious_data).call

        existing.reload
        expect(existing.user_id).to eq(user.id)
        expect(existing.id).not_to eq(999_999)
        expect(existing.distance).to eq(1500)
        expect(existing.start_at).to eq(start_at)
        expect(existing.end_at).to eq(end_at)
      end
    end

    context 'when refresh path receives segments' do
      let(:start_at) { Time.zone.parse('2024-03-01T08:00:00Z') }
      let(:end_at) { Time.zone.parse('2024-03-01T09:00:00Z') }
      let(:tracks_data) do
        [
          {
            'start_at' => start_at,
            'end_at' => end_at,
            'original_path' => 'LINESTRING(-74.006 40.7128, -74.007 40.713)',
            'distance' => 2500,
            'avg_speed' => 30.0,
            'duration' => 3600,
            'segments' => [
              {
                'transportation_mode' => 'walking', 'start_index' => 0, 'end_index' => 5,
                'distance' => 1000, 'duration' => 1800, 'avg_speed' => 5.0
              },
              {
                'transportation_mode' => 'cycling', 'start_index' => 6, 'end_index' => 12,
                'distance' => 1500, 'duration' => 1800, 'avg_speed' => 20.0
              }
            ]
          }
        ]
      end

      it 'replaces stale segments with the imported ones' do
        existing = create(:track, user: user, start_at: start_at, end_at: end_at, distance: 100)
        create(:track_segment, track: existing, transportation_mode: :driving)
        allow(Rails.logger).to receive(:info)

        described_class.new(user, tracks_data).call

        existing.reload
        expect(existing.distance).to eq(2500)
        expect(existing.track_segments.pluck(:transportation_mode)).to contain_exactly('walking', 'cycling')
        expect(Rails.logger).to have_received(:info).with(/Updated: 1/)
      end
    end

    context 'when refresh update raises RecordInvalid mid-iteration' do
      let(:start_at) { Time.zone.parse('2024-04-01T08:00:00Z') }
      let(:end_at) { Time.zone.parse('2024-04-01T09:00:00Z') }
      let(:tracks_data) do
        [
          {
            'start_at' => start_at,
            'end_at' => end_at,
            'original_path' => 'LINESTRING(-74.006 40.7128, -74.007 40.713)',
            'distance' => 9999,
            'avg_speed' => 30.0,
            'duration' => 3600
          },
          {
            'start_at' => Time.zone.parse('2024-04-02T08:00:00Z'),
            'end_at' => Time.zone.parse('2024-04-02T09:00:00Z'),
            'original_path' => 'LINESTRING(-74.006 40.7128, -74.007 40.713)',
            'distance' => 1000,
            'avg_speed' => 25.0,
            'duration' => 3600
          }
        ]
      end

      it 'logs and continues importing subsequent tracks' do
        create(:track, user: user, start_at: start_at, end_at: end_at, distance: 100)

        allow_any_instance_of(Track).to receive(:update!).and_wrap_original do |original, *args|
          raise ActiveRecord::RecordInvalid, Track.new if args.first.is_a?(Hash) && args.first['distance'] == 9999

          original.call(*args)
        end
        allow(ExceptionReporter).to receive(:call)
        allow(Rails.logger).to receive(:info)

        expect { described_class.new(user, tracks_data).call }.not_to raise_error
        expect(user.tracks.where(start_at: Time.zone.parse('2024-04-02T08:00:00Z'))).to exist
        expect(Rails.logger).to have_received(:info).with(/Failed refresh: 1/)
      end

      it 'rescues a fresh RecordNotUnique raised from update! and continues' do
        create(:track, user: user, start_at: start_at, end_at: end_at, distance: 100)

        allow_any_instance_of(Track).to receive(:update!).and_wrap_original do |original, *args|
          raise ActiveRecord::RecordNotUnique, 'collision' if args.first.is_a?(Hash) && args.first['distance'] == 9999

          original.call(*args)
        end
        allow(ExceptionReporter).to receive(:call)
        allow(Rails.logger).to receive(:info)

        expect { described_class.new(user, tracks_data).call }.not_to raise_error
        expect(user.tracks.where(start_at: Time.zone.parse('2024-04-02T08:00:00Z'))).to exist
        expect(Rails.logger).to have_received(:info).with(/Failed refresh: 1/)
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
