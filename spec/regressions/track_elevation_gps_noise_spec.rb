# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Track elevation with GPS altitude noise' do
  let(:user) { create(:user) }
  let(:builder) do
    Class.new do
      include Tracks::TrackBuilder

      def initialize(user)
        @user = user
      end

      private

      attr_reader :user
    end.new(user)
  end

  it 'does not turn repeated altitude noise into hundreds of meters of ascent and descent' do
    # Ground truth: a level route at 100 m, then a gradual ascent to 113 m.
    # The repeated 10 m and 5 m spikes are synthetic GPS measurement noise,
    # smaller than the reported vertical uncertainty of 20 m.
    altitudes = [100] + ([110, 100] * 12) + [105, 100, 104, 108, 113]
    start_at = Time.zone.parse('2026-10-10 12:00:00').to_i
    points = altitudes.each_with_index.map do |altitude, index|
      create(:point, user: user, altitude: altitude, vertical_accuracy: 20, accuracy: 5,
                     lonlat: "POINT(#{-140.0 + index * 0.001} -45.0)",
                     timestamp: start_at + index * 30, tracker_id: 'synthetic-elevation-noise',
                     reverse_geocoded_at: Time.current)
    end

    track = builder.create_track_from_points(points, 2280, skip_segment_detection: true)

    expect(track).to be_persisted
    track.reload
    # Allow 10 m of estimation error without prescribing a smoothing algorithm.
    aggregate_failures do
      expect(track.elevation_gain).to be_within(10).of(13)
      expect(track.elevation_loss).to be <= 10
    end
  end
end
