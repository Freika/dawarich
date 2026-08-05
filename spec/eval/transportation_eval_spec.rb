# frozen_string_literal: true

require 'rails_helper'

# Labeled-scenario evaluation of the transportation mode detection pipeline.
# Excluded from normal runs; execute with: bundle exec rspec spec/eval --tag eval
EVAL_SCENARIOS = {
  'walk' => [{ mode: :walking, duration_s: 900, dt_s: 5 }],
    'commute_mixed' => [{ mode: :walking, duration_s: 300, dt_s: 5 },
                        { mode: :driving, duration_s: 900, dt_s: 5 },
                        { mode: :walking, duration_s: 300, dt_s: 5 }],
    'run' => [{ mode: :running, duration_s: 1200, dt_s: 5 }],
    'bike_errand' => [{ mode: :walking, duration_s: 180, dt_s: 5 },
                      { mode: :cycling, duration_s: 900, dt_s: 5 }],
    'train_trip' => [{ mode: :walking, duration_s: 300, dt_s: 10 },
                     { mode: :train, duration_s: 1800, dt_s: 10 },
                     { mode: :walking, duration_s: 300, dt_s: 10 }],
    'sparse_drive' => [{ mode: :driving, duration_s: 1800, dt_s: 60 }]
}.freeze

RSpec.describe 'Transportation mode eval', :eval do
  def relative_timeline(entries, trip)
    origin = trip[:points].first[:timestamp]
    entries.map { |e| [e[:mode], e[:start_ts] - origin, e[:end_ts] - origin] }
  end

  it 'scores the detection pipeline on labeled synthetic trips' do
    user = create(:user)
    report = {}

    EVAL_SCENARIOS.each_with_index do |(name, legs), scenario_index|
      # Distinct day + seed per scenario: identical (user, lonlat, timestamp)
      # rows would be silently dropped by insert_all's conflict handling.
      trip = TransportationTraceGenerator.trip(
        legs: legs,
        start_time: Time.zone.parse('2026-01-05 09:00 UTC') + scenario_index.days,
        seed: 42 + scenario_index
      )
      track = create(:track, user: user,
                             start_at: Time.zone.at(trip[:points].first[:timestamp]),
                             end_at: Time.zone.at(trip[:points].last[:timestamp]))
      now = Time.current
      rows = trip[:points].map do |p|
        { user_id: user.id, track_id: track.id, timestamp: p[:timestamp],
          lonlat: "SRID=4326;POINT(#{p[:lon]} #{p[:lat]})",
          accuracy: p[:accuracy], velocity: p[:velocity].to_s,
          created_at: now, updated_at: now }
      end
      Point.insert_all(rows)

      segments = TransportationModes::Detector.new(track).call
      predicted = segments.map do |s|
        { mode: s[:mode].to_sym, start_ts: s[:start_at].to_i, end_ts: s[:end_at].to_i }
      end

      report[name] = TransportationModes::EvalScorer.score(
        predicted: predicted, labels: trip[:labels], points: trip[:points]
      ).merge(
        predicted: relative_timeline(predicted, trip),
        labels: relative_timeline(trip[:labels], trip)
      )
    end

    File.write(Rails.root.join('tmp/transportation_eval_report.json'), JSON.pretty_generate(report))
    puts JSON.pretty_generate(report)
    expect(report.size).to eq(EVAL_SCENARIOS.size)
  end
end
