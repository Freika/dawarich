# frozen_string_literal: true

module TransportationModes
  # Cleans FeatureExtractor rows into per-point speeds the classifier can
  # trust: stored velocity wins (including 0.0 — parked points must not
  # inherit GPS-drift speeds), derived dist/dt is the fallback, and samples
  # are invalidated on poor accuracy, zero dt, or implausible acceleration.
  class Preprocessor
    def self.call(rows)
      SpeedCalibrator.call(rows)

      previous_valid_speed = nil
      processed = rows.map do |input_row|
        row = input_row.merge(speed_mps: nil, speed_valid: false, bearing_delta_deg: nil)
        resolve_speed(row, previous_valid_speed)
        previous_valid_speed = row[:speed_mps] if row[:speed_valid]
        row
      end

      processed.each_cons(2) do |prev, current|
        next if prev[:bearing_deg].nil? || current[:bearing_deg].nil?

        current[:bearing_delta_deg] = circular_delta(prev[:bearing_deg], current[:bearing_deg])
      end
      processed
    end

    def self.resolve_speed(row, previous_valid_speed)
      # Negative stored velocity marks an anomalous fix (iOS CLLocation /
      # Traccar Client JSON report -1 when unreliable). The whole sample is
      # masked — deriving a speed from a suspect fix would launder it.
      stored = row[:velocity]
      return if stored&.negative?

      speed = stored || derived_speed(row)
      return if speed.nil?

      row[:speed_mps] = speed
      row[:speed_valid] = valid_sample?(row, speed, previous_valid_speed, stored)
    end

    def self.derived_speed(row)
      return nil if row[:dt].nil? || row[:dt] <= 0 || row[:dist_m].nil?

      row[:dist_m] / row[:dt]
    end

    def self.valid_sample?(row, speed, previous_valid_speed, stored)
      return false if row[:accuracy].present? && row[:accuracy] > Emissions::TUNING[:accuracy_mask_m]
      return true if stored
      return false if row[:dt].nil? || row[:dt] <= 0

      plausible_acceleration?(speed, previous_valid_speed, row[:dt])
    end

    def self.plausible_acceleration?(speed, previous_valid_speed, delta_seconds)
      return true if previous_valid_speed.nil?

      ((speed - previous_valid_speed).abs / delta_seconds) <= Emissions::TUNING[:accel_mask_mps2]
    end

    def self.circular_delta(bearing_a, bearing_b)
      delta = (bearing_b - bearing_a).abs % 360.0
      delta > 180.0 ? 360.0 - delta : delta
    end
  end
end
