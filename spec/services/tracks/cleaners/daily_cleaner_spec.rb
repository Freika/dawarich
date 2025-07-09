# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::Cleaners::DailyCleaner do
  let(:user) { create(:user) }
  let(:start_at) { 1.day.ago.beginning_of_day }
  let(:end_at) { 1.day.ago.end_of_day }
  let(:cleaner) { described_class.new(user, start_at: start_at.to_i, end_at: end_at.to_i) }

  describe '#cleanup' do
    context 'when there are no overlapping tracks' do
      before do
        # Create a track that ends before our window
        track = create(:track, user: user, start_at: 2.days.ago, end_at: 2.days.ago + 1.hour)
        create(:point, user: user, track: track, timestamp: 2.days.ago.to_i)
      end

      it 'does not remove any tracks' do
        expect { cleaner.cleanup }.not_to change { user.tracks.count }
      end
    end

    context 'when a track is completely within the time window' do
      let!(:track) { create(:track, user: user, start_at: start_at + 1.hour, end_at: end_at - 1.hour) }
      let!(:point1) { create(:point, user: user, track: track, timestamp: (start_at + 1.hour).to_i) }
      let!(:point2) { create(:point, user: user, track: track, timestamp: (start_at + 2.hours).to_i) }

      it 'removes all points from the track and deletes it' do
        expect { cleaner.cleanup }.to change { user.tracks.count }.by(-1)
        expect(point1.reload.track_id).to be_nil
        expect(point2.reload.track_id).to be_nil
      end
    end

    context 'when a track spans across the time window' do
      let!(:track) { create(:track, user: user, start_at: start_at - 1.hour, end_at: end_at + 1.hour) }
      let!(:point_before) { create(:point, user: user, track: track, timestamp: (start_at - 30.minutes).to_i) }
      let!(:point_during1) { create(:point, user: user, track: track, timestamp: (start_at + 1.hour).to_i) }
      let!(:point_during2) { create(:point, user: user, track: track, timestamp: (start_at + 2.hours).to_i) }
      let!(:point_after) { create(:point, user: user, track: track, timestamp: (end_at + 30.minutes).to_i) }

      it 'removes only points within the window and updates track boundaries' do
        expect { cleaner.cleanup }.not_to change { user.tracks.count }

        # Points outside window should remain attached
        expect(point_before.reload.track_id).to eq(track.id)
        expect(point_after.reload.track_id).to eq(track.id)

        # Points inside window should be detached
        expect(point_during1.reload.track_id).to be_nil
        expect(point_during2.reload.track_id).to be_nil

        # Track boundaries should be updated
        track.reload
        expect(track.start_at).to be_within(1.second).of(Time.zone.at(point_before.timestamp))
        expect(track.end_at).to be_within(1.second).of(Time.zone.at(point_after.timestamp))
      end
    end

    context 'when a track overlaps but has insufficient remaining points' do
      let!(:track) { create(:track, user: user, start_at: start_at - 1.hour, end_at: end_at + 1.hour) }
      let!(:point_before) { create(:point, user: user, track: track, timestamp: (start_at - 30.minutes).to_i) }
      let!(:point_during) { create(:point, user: user, track: track, timestamp: (start_at + 1.hour).to_i) }

      it 'removes the track entirely and orphans remaining points' do
        expect { cleaner.cleanup }.to change { user.tracks.count }.by(-1)

        expect(point_before.reload.track_id).to be_nil
        expect(point_during.reload.track_id).to be_nil
      end
    end

    context 'when track has no points in the time window' do
      let!(:track) { create(:track, user: user, start_at: start_at - 2.hours, end_at: end_at + 2.hours) }
      let!(:point_before) { create(:point, user: user, track: track, timestamp: (start_at - 30.minutes).to_i) }
      let!(:point_after) { create(:point, user: user, track: track, timestamp: (end_at + 30.minutes).to_i) }

      it 'does not modify the track' do
        expect { cleaner.cleanup }.not_to change { user.tracks.count }
        expect(track.reload.start_at).to be_within(1.second).of(track.start_at)
        expect(track.reload.end_at).to be_within(1.second).of(track.end_at)
      end
    end

    context 'without start_at and end_at' do
      let(:cleaner) { described_class.new(user) }

      it 'does not perform any cleanup' do
        create(:track, user: user)
        expect { cleaner.cleanup }.not_to change { user.tracks.count }
      end
    end
  end
end
