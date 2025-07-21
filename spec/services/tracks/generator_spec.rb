# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::Generator do
  let(:user) { create(:user) }
  let(:safe_settings) { user.safe_settings }

  before do
    allow(user).to receive(:safe_settings).and_return(safe_settings)
  end

  describe '#call' do
    context 'with bulk mode' do
      let(:generator) { described_class.new(user, mode: :bulk) }

      context 'with sufficient points' do
        let!(:points) { create_points_around(user: user, count: 5, base_lat: 20.0) }

        it 'generates tracks from all points' do
          expect { generator.call }.to change(Track, :count).by(1)
        end

        it 'cleans existing tracks' do
          existing_track = create(:track, user: user)
          generator.call
          expect(Track.exists?(existing_track.id)).to be false
        end

        it 'associates points with created tracks' do
          generator.call
          expect(points.map(&:reload).map(&:track)).to all(be_present)
        end

        it 'properly handles point associations when cleaning existing tracks' do
          # Create existing tracks with associated points
          existing_track = create(:track, user: user)
          existing_points = create_list(:point, 3, user: user, track: existing_track)

          # Verify points are associated
          expect(existing_points.map(&:reload).map(&:track_id)).to all(eq(existing_track.id))

          # Run generator which should clean existing tracks and create new ones
          generator.call

          # Verify the old track is deleted
          expect(Track.exists?(existing_track.id)).to be false

          # Verify the points are no longer associated with the deleted track
          expect(existing_points.map(&:reload).map(&:track_id)).to all(be_nil)
        end
      end

      context 'with insufficient points' do
        let!(:points) { create_points_around(user: user, count: 1, base_lat: 20.0) }

        it 'does not create tracks' do
          expect { generator.call }.not_to change(Track, :count)
        end
      end

      context 'with time range' do
        let!(:old_points) { create_points_around(user: user, count: 3, base_lat: 20.0, timestamp: 2.days.ago.to_i) }
        let!(:new_points) { create_points_around(user: user, count: 3, base_lat: 21.0, timestamp: 1.day.ago.to_i) }

        it 'only processes points within range' do
          generator = described_class.new(
            user,
            start_at: 1.day.ago.beginning_of_day,
            end_at: 1.day.ago.end_of_day,
            mode: :bulk
          )

          generator.call
          track = Track.last
          expect(track.points.count).to eq(3)
        end
      end
    end

    context 'with incremental mode' do
      let(:generator) { described_class.new(user, mode: :incremental) }

      context 'with untracked points' do
        let!(:points) { create_points_around(user: user, count: 3, base_lat: 22.0, track_id: nil) }

        it 'processes untracked points' do
          expect { generator.call }.to change(Track, :count).by(1)
        end

        it 'associates points with created tracks' do
          generator.call
          expect(points.map(&:reload).map(&:track)).to all(be_present)
        end
      end

      context 'with end_at specified' do
        let!(:early_points) { create_points_around(user: user, count: 2, base_lat: 23.0, timestamp: 2.hours.ago.to_i) }
        let!(:late_points) { create_points_around(user: user, count: 2, base_lat: 24.0, timestamp: 1.hour.ago.to_i) }

        it 'only processes points up to end_at' do
          generator = described_class.new(user, end_at: 1.5.hours.ago, mode: :incremental)
          generator.call

          expect(Track.count).to eq(1)
          expect(Track.first.points.count).to eq(2)
        end
      end

      context 'without existing tracks' do
        let!(:points) { create_points_around(user: user, count: 3, base_lat: 25.0) }

        it 'does not clean existing tracks' do
          existing_track = create(:track, user: user)
          generator.call
          expect(Track.exists?(existing_track.id)).to be true
        end
      end
    end

    context 'with daily mode' do
      let(:today) { Date.current }
      let(:generator) { described_class.new(user, start_at: today, mode: :daily) }

      let!(:today_points) { create_points_around(user: user, count: 3, base_lat: 26.0, timestamp: today.beginning_of_day.to_i) }
      let!(:yesterday_points) { create_points_around(user: user, count: 3, base_lat: 27.0, timestamp: 1.day.ago.to_i) }

      it 'only processes points from specified day' do
        generator.call
        track = Track.last
        expect(track.points.count).to eq(3)
      end

      it 'cleans existing tracks for the day' do
        existing_track = create(:track, user: user, start_at: today.beginning_of_day)
        generator.call
        expect(Track.exists?(existing_track.id)).to be false
      end

      it 'properly handles point associations when cleaning daily tracks' do
        # Create existing tracks with associated points for today
        existing_track = create(:track, user: user, start_at: today.beginning_of_day)
        existing_points = create_list(:point, 3, user: user, track: existing_track)

        # Verify points are associated
        expect(existing_points.map(&:reload).map(&:track_id)).to all(eq(existing_track.id))

        # Run generator which should clean existing tracks for the day and create new ones
        generator.call

        # Verify the old track is deleted
        expect(Track.exists?(existing_track.id)).to be false

        # Verify the points are no longer associated with the deleted track
        expect(existing_points.map(&:reload).map(&:track_id)).to all(be_nil)
      end
    end

    context 'with empty points' do
      let(:generator) { described_class.new(user, mode: :bulk) }

      it 'does not create tracks' do
        expect { generator.call }.not_to change(Track, :count)
      end
    end

    context 'with threshold configuration' do
      let(:generator) { described_class.new(user, mode: :bulk) }

      before do
        allow(safe_settings).to receive(:meters_between_routes).and_return(1000)
        allow(safe_settings).to receive(:minutes_between_routes).and_return(90)
      end

      it 'uses configured thresholds' do
        expect(generator.send(:distance_threshold_meters)).to eq(1000)
        expect(generator.send(:time_threshold_minutes)).to eq(90)
      end
    end

    context 'with invalid mode' do
      it 'raises argument error' do
        expect do
          described_class.new(user, mode: :invalid).call
        end.to raise_error(ArgumentError, /Unknown mode/)
      end
    end
  end

  describe 'segmentation behavior' do
    let(:generator) { described_class.new(user, mode: :bulk) }

    context 'with points exceeding time threshold' do
      let!(:points) do
        [
          create_points_around(user: user, count: 1, base_lat: 29.0, timestamp: 90.minutes.ago.to_i),
          create_points_around(user: user, count: 1, base_lat: 29.0, timestamp: 60.minutes.ago.to_i),
          # Gap exceeds threshold 👇👇👇
          create_points_around(user: user, count: 1, base_lat: 29.0, timestamp: 10.minutes.ago.to_i),
          create_points_around(user: user, count: 1, base_lat: 29.0, timestamp: Time.current.to_i)
        ]
      end

      before do
        allow(safe_settings).to receive(:minutes_between_routes).and_return(45)
      end

      it 'creates separate tracks for segments' do
        expect { generator.call }.to change(Track, :count).by(2)
      end
    end

    context 'with points exceeding distance threshold' do
      let!(:points) do
        [
          create_points_around(user: user, count: 2, base_lat: 29.0, timestamp: 20.minutes.ago.to_i),
          create_points_around(user: user, count: 2, base_lat: 29.0, timestamp: 15.minutes.ago.to_i),
          # Large distance jump 👇👇👇
          create_points_around(user: user, count: 2, base_lat: 28.0, timestamp: 10.minutes.ago.to_i),
          create_points_around(user: user, count: 1, base_lat: 28.0, timestamp: Time.current.to_i)
        ]
      end

      before do
        allow(safe_settings).to receive(:meters_between_routes).and_return(200)
      end

      it 'creates separate tracks for segments' do
        expect { generator.call }.to change(Track, :count).by(2)
      end
    end
  end

  describe 'deterministic behavior' do
    let!(:points) { create_points_around(user: user, count: 10, base_lat: 28.0) }

    it 'produces same results for bulk and incremental modes' do
      # Generate tracks in bulk mode
      bulk_generator = described_class.new(user, mode: :bulk)
      bulk_generator.call
      bulk_tracks = user.tracks.order(:start_at).to_a

      # Clear tracks and generate incrementally
      user.tracks.destroy_all
      incremental_generator = described_class.new(user, mode: :incremental)
      incremental_generator.call
      incremental_tracks = user.tracks.order(:start_at).to_a

      # Should have same number of tracks
      expect(incremental_tracks.size).to eq(bulk_tracks.size)

      # Should have same track boundaries (allowing for small timing differences)
      bulk_tracks.zip(incremental_tracks).each do |bulk_track, incremental_track|
        expect(incremental_track.start_at).to be_within(1.second).of(bulk_track.start_at)
        expect(incremental_track.end_at).to be_within(1.second).of(bulk_track.end_at)
        expect(incremental_track.distance).to be_within(10).of(bulk_track.distance)
      end
    end
  end
end
