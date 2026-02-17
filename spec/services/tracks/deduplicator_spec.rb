# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::Deduplicator do
  let(:user) { create(:user) }

  describe '#call' do
    context 'when user has no tracks' do
      it 'returns 0' do
        expect(described_class.new(user).call).to eq(0)
      end
    end

    context 'when no duplicates exist' do
      before do
        create(:track, user: user, start_at: 2.hours.ago, end_at: 1.hour.ago)
        create(:track, user: user, start_at: 3.hours.ago, end_at: 2.hours.ago)
      end

      it 'returns 0' do
        expect(described_class.new(user).call).to eq(0)
      end

      it 'does not delete any tracks' do
        expect { described_class.new(user).call }.not_to(change { user.tracks.count })
      end
    end

    context 'when duplicates exist' do
      let(:start_time) { 2.hours.ago }
      let(:end_time) { 1.hour.ago }

      let!(:older_track) { create(:track, user: user, start_at: start_time, end_at: end_time) }
      let!(:newer_track) { create(:track, user: user, start_at: start_time, end_at: end_time) }
      let!(:unique_track) { create(:track, user: user, start_at: 3.hours.ago, end_at: 2.hours.ago) }

      it 'deletes duplicates keeping the highest id' do
        described_class.new(user).call

        expect(Track.exists?(older_track.id)).to be false
        expect(Track.exists?(newer_track.id)).to be true
        expect(Track.exists?(unique_track.id)).to be true
      end

      it 'returns the number of deleted tracks' do
        expect(described_class.new(user).call).to eq(1)
      end

      it 'deletes orphaned segments for removed tracks' do
        segment = create(:track_segment, track: older_track)
        keeper_segment = create(:track_segment, track: newer_track)

        described_class.new(user).call

        expect(TrackSegment.exists?(segment.id)).to be false
        expect(TrackSegment.exists?(keeper_segment.id)).to be true
      end

      it 'logs the removal count' do
        allow(Rails.logger).to receive(:info)

        described_class.new(user).call

        expect(Rails.logger).to have_received(:info).with(/Removed 1 duplicate tracks for user #{user.id}/)
      end
    end

    context 'when another user has tracks with the same timestamps' do
      let(:other_user) { create(:user) }
      let(:start_time) { 2.hours.ago }
      let(:end_time) { 1.hour.ago }

      let!(:user_track) { create(:track, user: user, start_at: start_time, end_at: end_time) }
      let!(:other_user_track) { create(:track, user: other_user, start_at: start_time, end_at: end_time) }

      it 'does not affect other users tracks' do
        described_class.new(user).call

        expect(Track.exists?(other_user_track.id)).to be true
      end
    end
  end
end
