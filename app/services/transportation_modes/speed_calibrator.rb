# frozen_string_literal: true

module TransportationModes
  # Per-track sanity check for stored velocities: compares them against
  # GPS-derived speeds and rescales when the tracker clearly reports km/h,
  # knots, or mph where the pipeline expects m/s. This immunizes detection
  # against per-source unit bugs, present and future (e.g. OsmAnd-style
  # trackers posting through the OwnTracks endpoint). A ratio matching no
  # band leaves velocities untouched — noisy m/s traces routinely drift
  # outside the m/s band, and nulling them would throw away the trace's
  # best speed signal (per-sample accuracy masks still apply downstream).
  class SpeedCalibrator
    MIN_SAMPLES = 20
    MIN_DERIVED_MPS = 1.0

    # unit => [scale-to-m/s, the median stored/derived ratio band identifying it]
    UNIT_BANDS = {
      mps: [1.0, (0.8...1.25)],
      knots: [1.0 / 1.944, (1.7...2.09)],
      mph: [1.0 / 2.237, (2.09...2.5)],
      kmh: [1.0 / 3.6, (3.0...4.3)]
    }.freeze

    def self.call(rows)
      ratio = median_ratio(rows)
      return rows if ratio.nil?

      unit, (scale, _band) = UNIT_BANDS.find { |_unit, (_scale, band)| band.cover?(ratio) }
      return rows if unit.nil? || unit == :mps

      rows.each do |row|
        velocity = row[:velocity]
        next if velocity.nil? || velocity.negative?

        row[:velocity] = velocity * scale
      end
      rows
    end

    def self.median_ratio(rows)
      samples = rows.filter_map do |row|
        velocity = row[:velocity]
        next nil if velocity.nil? || velocity <= 0
        next nil if row[:dt].nil? || row[:dt] <= 0 || row[:dist_m].nil?

        derived = row[:dist_m] / row[:dt]
        next nil if derived < MIN_DERIVED_MPS

        velocity / derived
      end
      return nil if samples.size < MIN_SAMPLES

      samples.sort[samples.size / 2]
    end
  end
end
