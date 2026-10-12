# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BoundaryDetector do
  let(:user) { create(:user) }
  let(:detector) { described_class.new(user) }
  let(:tracker) { 'device-1' }
  let(:base_time) { 1.hour.ago }

  context 'when there are no untracked points in the lookback window' do
    let!(:track) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: base_time,
                     end_at: base_time + 30.seconds)
    end

    before do
      create(:point, user: user, tracker_id: tracker,
                     timestamp: base_time.to_i,
                     lonlat: 'POINT(13.40 52.52)',
                     track: track)
      create(:point, user: user, tracker_id: tracker,
                     timestamp: (base_time + 30.seconds).to_i,
                     lonlat: 'POINT(13.41 52.53)',
                     track: track)
    end

    it 'short-circuits reabsorb_orphan_points without iterating recent tracks' do
      expect(user.tracks).not_to receive(:find_each)

      expect(detector.reabsorb_orphan_points).to eq(0)
    end
  end

  context 'when an untracked point exists in the lookback window' do
    let!(:track) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: base_time,
                     end_at: base_time + 60.seconds)
    end

    before do
      create(:point, user: user, tracker_id: tracker,
                     timestamp: base_time.to_i,
                     lonlat: 'POINT(13.40 52.52)',
                     track: track)
      create(:point, user: user, tracker_id: tracker,
                     timestamp: (base_time + 60.seconds).to_i,
                     lonlat: 'POINT(13.41 52.53)',
                     track: track)

      create(:point, user: user, tracker_id: tracker,
                     timestamp: (base_time + 30.seconds).to_i,
                     lonlat: 'POINT(13.405 52.525)',
                     track: nil,
                     created_at: 2.minutes.ago)
    end

    it 'runs the absorb loop and absorbs the orphan into the track' do
      expect { detector.reabsorb_orphan_points }
        .to change { track.reload.points.count }.from(2).to(3)
    end
  end
end
