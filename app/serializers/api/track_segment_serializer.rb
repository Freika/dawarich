# frozen_string_literal: true

class Api::TrackSegmentSerializer
  def initialize(segment)
    @segment = segment
  end

  def call
    {
      id: segment.id,
      track_id: segment.track_id,
      transportation_mode: segment.transportation_mode,
      start_at: segment.start_at&.iso8601,
      end_at: segment.end_at&.iso8601,
      start_index: segment.start_index,
      end_index: segment.end_index,
      distance: segment.distance,
      duration: segment.duration,
      avg_speed: segment.avg_speed&.to_f,
      max_speed: segment.max_speed&.to_f,
      confidence: segment.confidence,
      confidence_score: segment.confidence_score&.to_f,
      source: segment.source,
      corrected_at: segment.corrected_at&.iso8601,
      manually_corrected: segment.manually_corrected?
    }
  end

  private

  attr_reader :segment
end
