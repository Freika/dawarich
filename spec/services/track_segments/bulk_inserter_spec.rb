# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrackSegments::BulkInserter do
  let(:user) { create(:user) }
  let(:track) { create(:track, user: user) }

  let(:segment_data) do
    [
      {
        mode: :walking,
        start_at: Time.zone.at(1_000), end_at: Time.zone.at(1_300),
        path_wkt: 'LINESTRING(12.3712 51.3402, 12.3722 51.3402)',
        distance: 500, duration: 300,
        avg_speed: 5.0, max_speed: 7.0,
        confidence: :medium, confidence_score: 0.65,
        source: 'inferred'
      },
      {
        mode: :driving,
        start_at: Time.zone.at(1_300), end_at: Time.zone.at(1_900),
        path_wkt: 'LINESTRING(12.3722 51.3402, 12.3922 51.3502)',
        distance: 12_000, duration: 600,
        avg_speed: 30.0, max_speed: 50.0,
        confidence: :high, confidence_score: 0.92,
        source: 'hints+inferred'
      }
    ]
  end

  describe '.call' do
    it 'creates one row per segment' do
      expect { described_class.call(track, segment_data) }
        .to change { track.track_segments.count }.from(0).to(2)
    end

    it 'writes time anchors, geometry and confidence to the database' do
      described_class.call(track, segment_data)

      walking, driving = track.track_segments.order(:start_at).to_a

      expect(walking).to have_attributes(
        transportation_mode: 'walking',
        distance: 500, duration: 300,
        confidence: 'medium', source: 'inferred'
      )
      expect(walking.start_at.to_i).to eq(1_000)
      expect(walking.end_at.to_i).to eq(1_300)
      expect(walking.confidence_score).to eq(0.65)
      expect(walking.path.points.size).to eq(2)
      expect(walking.start_index).to be_nil

      expect(driving.transportation_mode).to eq('driving')
      expect(driving.confidence_score).to eq(0.92)
    end

    it 'is idempotent on (track_id, start_at)' do
      described_class.call(track, segment_data)
      expect { described_class.call(track, segment_data) }
        .not_to(change { track.track_segments.count })
    end

    it 'handles nil path for degenerate segments' do
      data = [segment_data.first.merge(path_wkt: nil)]
      described_class.call(track, data)
      expect(track.track_segments.first.path).to be_nil
    end

    it 'returns empty array for empty input' do
      expect(described_class.call(track, [])).to eq([])
    end
  end
end
