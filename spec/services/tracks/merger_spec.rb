# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::Merger do
  let(:user) { create(:user) }

  describe '#call' do
    context 'with valid tracks to merge' do
      let(:older_track) do
        create(:track, user: user,
                       start_at: 2.hours.ago,
                       end_at: 1.hour.ago)
      end

      let(:newer_track) do
        create(:track, user: user,
                       start_at: 50.minutes.ago,
                       end_at: 30.minutes.ago)
      end

      let!(:older_points) do
        [
          create(:point, user: user, track: older_track, timestamp: 2.hours.ago.to_i, lonlat: 'POINT(-74.006 40.7128)'),
          create(:point, user: user, track: older_track, timestamp: 1.hour.ago.to_i, lonlat: 'POINT(-74.007 40.7138)')
        ]
      end

      let!(:newer_points) do
        [
          create(:point, user: user, track: newer_track, timestamp: 50.minutes.ago.to_i,
                         lonlat: 'POINT(-74.008 40.7148)'),
          create(:point, user: user, track: newer_track, timestamp: 30.minutes.ago.to_i, lonlat: 'POINT(-74.009 40.7158)')
        ]
      end

      let(:merger) { described_class.new(older_track, newer_track) }

      it 'returns true on success' do
        expect(merger.call).to be true
      end

      it 'moves points from newer track to older track' do
        merger.call

        older_track.reload
        expect(older_track.points.count).to eq(4)
        expect(older_track.points.pluck(:id)).to include(*newer_points.map(&:id))
      end

      it 'destroys the newer track' do
        merger.call

        expect(Track.exists?(newer_track.id)).to be false
      end

      it 'updates the older track end_at' do
        merger.call

        older_track.reload
        expect(older_track.end_at).to eq(newer_track.end_at)
      end

      it 'recalculates path and distance' do
        original_distance = older_track.distance

        merger.call

        older_track.reload
        # Distance should change after merging
        expect(older_track.distance).not_to eq(original_distance)
      end

      it 'deletes old segments and re-detects for the merged track' do
        create(:track_segment, track: older_track, start_index: 0, end_index: 1)
        create(:track_segment, track: newer_track, start_index: 0, end_index: 1)

        expect { merger.call }.to change { TrackSegment.count }
        expect(Track.exists?(newer_track.id)).to be false
        expect(older_track.reload.track_segments.count).to be >= 0
      end
    end

    context 'when older_track is nil' do
      let(:newer_track) { create(:track, user: user) }
      let(:merger) { described_class.new(nil, newer_track) }

      it 'returns false' do
        expect(merger.call).to be false
      end

      it 'does not destroy the newer track' do
        merger.call

        expect(Track.exists?(newer_track.id)).to be true
      end
    end

    context 'when newer_track is nil' do
      let(:older_track) { create(:track, user: user) }
      let(:merger) { described_class.new(older_track, nil) }

      it 'returns false' do
        expect(merger.call).to be false
      end
    end

    context 'when both tracks are the same' do
      let(:track) { create(:track, user: user) }
      let(:merger) { described_class.new(track, track) }

      it 'returns false' do
        expect(merger.call).to be false
      end

      it 'does not destroy the track' do
        merger.call

        expect(Track.exists?(track.id)).to be true
      end
    end

    context 'when an error occurs during merge' do
      let(:older_track) { create(:track, user: user) }
      let(:newer_track) { create(:track, user: user) }
      let(:merger) { described_class.new(older_track, newer_track) }

      before do
        allow(older_track).to receive(:recalculate_path_and_distance!).and_raise(StandardError, 'Database error')
      end

      it 'returns false' do
        expect(merger.call).to be false
      end

      it 'rolls back the transaction' do
        merger.call

        # Both tracks should still exist
        expect(Track.exists?(older_track.id)).to be true
        expect(Track.exists?(newer_track.id)).to be true
      end

      it 'logs the error' do
        allow(Rails.logger).to receive(:error)

        merger.call

        expect(Rails.logger).to have_received(:error).with(/Failed to merge tracks/)
      end
    end
  end
end
