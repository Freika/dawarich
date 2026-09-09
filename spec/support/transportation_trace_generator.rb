# frozen_string_literal: true

# Deterministic GPS trace generator for transportation mode tests and eval.
# Coordinates start in Leipzig; timestamps are epoch seconds.
module TransportationTraceGenerator
  START = { lat: 51.3402, lon: 12.3712 }.freeze
  # speed m/s, jitter m/s (uniform), wobble deg (heading noise), acc m (gps accuracy)
  PROFILES = {
    stationary: { speed: 0.05, jitter: 0.1, wobble: 180, acc: 15.0 },
    walking: { speed: 1.3, jitter: 0.3, wobble: 30, acc: 8.0 },
    running: { speed: 2.9, jitter: 0.4, wobble: 15, acc: 8.0 },
    cycling: { speed: 4.8, jitter: 0.8, wobble: 8, acc: 6.0 },
    driving: { speed: 12.0, jitter: 4.0, wobble: 4, acc: 6.0 },
    train: { speed: 27.0, jitter: 3.0, wobble: 1, acc: 12.0 },
    flying: { speed: 220.0, jitter: 15.0, wobble: 0.5, acc: 30.0 }
  }.freeze

  module_function

  def trip(legs:, start_time:, seed: 42)
    rng = Random.new(seed)
    ts = start_time.to_i
    lat = START[:lat]
    lon = START[:lon]
    heading = 90.0
    points = []
    labels = []

    legs.each do |leg|
      prof = PROFILES.fetch(leg[:mode])
      leg_start = ts
      (leg[:duration_s] / leg[:dt_s]).times do
        speed = [prof[:speed] + (rng.rand * prof[:jitter] * 2) - prof[:jitter], 0.0].max
        heading += (rng.rand * prof[:wobble] * 2) - prof[:wobble]
        dist = speed * leg[:dt_s]
        lat += (dist * Math.cos(heading * Math::PI / 180)) / 111_320.0
        lon += (dist * Math.sin(heading * Math::PI / 180)) / (111_320.0 * Math.cos(lat * Math::PI / 180))
        points << { lat: lat.round(7), lon: lon.round(7), timestamp: ts,
                    accuracy: prof[:acc], velocity: speed.round(2) }
        ts += leg[:dt_s]
      end
      labels << { mode: leg[:mode], start_ts: leg_start, end_ts: ts }
    end

    { points: points, labels: labels }
  end
end
