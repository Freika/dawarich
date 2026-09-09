# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Extracted segments span their track and set a dominant mode' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:track) { create(:track, user: user, dominant_mode: nil) }

  before do
    5.times do |i|
      create(:point, user: user, import_id: import.id, track_id: track.id,
                     timestamp: 1.hour.ago.to_i + (i * 60),
                     lonlat: "POINT(#{12.3712 + (i * 0.001)} #{51.3402 + (i * 0.001)})")
    end
  end

  def extracted_segment(confidence)
    EnhancedImport::Extracted::TrackSegment.new(
      start_index: 0,
      end_index: 0,
      transportation_mode: 'driving',
      confidence: confidence,
      source_label: 'google_phone_takeout'
    )
  end

  it 'stretches a degenerate segment across the track points' do
    segment, = EnhancedImport::Writers::SegmentWriter.new.upsert(track, extracted_segment(0.9))

    expect(segment.start_index).to eq(0)
    expect(segment.end_index).to eq(4)
  end

  describe 'confidence coming from Google as a string' do
    it 'maps HIGH to high' do
      segment, = EnhancedImport::Writers::SegmentWriter.new.upsert(track, extracted_segment('HIGH'))
      expect(segment.confidence).to eq('high')
    end

    it 'maps MEDIUM to medium' do
      segment, = EnhancedImport::Writers::SegmentWriter.new.upsert(track, extracted_segment('MEDIUM'))
      expect(segment.confidence).to eq('medium')
    end

    it 'still handles numeric probabilities' do
      segment, = EnhancedImport::Writers::SegmentWriter.new.upsert(track, extracted_segment(0.95))
      expect(segment.confidence).to eq('high')
    end
  end
end
