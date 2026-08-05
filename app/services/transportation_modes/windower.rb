# frozen_string_literal: true

module TransportationModes
  # Slices preprocessed point rows into overlapping time windows and computes
  # the feature vector the Decoder scores. Long gaps split the sequence into
  # independent chains (gap_before: true on the first window after a gap).
  class Windower
    def self.call(rows)
      chains(rows).flat_map.with_index do |chain, chain_index|
        chain_windows(chain[:rows]).map.with_index do |window, window_index|
          window[:gap_before] = chain_index.positive? && window_index.zero?
          window
        end
      end
    end

    def self.chains(rows)
      result = []
      current = []
      rows.each do |row|
        if current.any? && row[:dt] && row[:dt] > Emissions::TUNING[:gap_reset_s]
          result << { rows: current }
          current = []
        end
        current << row
      end
      result << { rows: current } if current.any?
      result
    end

    def self.chain_windows(rows)
      return [] if rows.empty?

      first_ts = rows.first[:ts]
      last_ts = rows.last[:ts]
      span = adaptive_span(rows)
      step = span / 2

      (first_ts..[last_ts - span, first_ts].max).step(step).filter_map do |window_start|
        window_rows = rows.select { |r| r[:ts] >= window_start && r[:ts] < window_start + span }
        build_window(window_rows, window_start, window_start + span)
      end
    end

    # Sparse chains (large dt) widen the window so every window still holds
    # enough samples: at 60s dt a fixed 60s window would contain one point.
    def self.adaptive_span(rows)
      dts = rows.filter_map { |r| r[:dt] }.reject(&:zero?)
      return Emissions::TUNING[:window_s] if dts.empty?

      mean_dt = dts.sum.to_f / dts.size
      [Emissions::TUNING[:window_s], (mean_dt * 3).ceil].max
    end

    def self.build_window(window_rows, start_ts, end_ts)
      valid = window_rows.select { |r| r[:speed_valid] }
      return nil if valid.size < 2

      speeds_kmh = valid.map { |r| r[:speed_mps] * 3.6 }.sort
      moving = speeds_kmh.select { |s| s > 2.0 }
      dts = window_rows.filter_map { |r| r[:dt] }.reject(&:zero?)

      {
        start_ts: start_ts, end_ts: end_ts,
        mean_dt: dts.empty? ? 0.0 : dts.sum.to_f / dts.size,
        speed_p50: percentile(speeds_kmh, 0.50),
        speed_p85: percentile(speeds_kmh, 0.85),
        speed_p95: percentile(speeds_kmh, 0.95),
        heading_change_rate: heading_change_rate(valid),
        motion_variance: standard_deviation(moving),
        stop_fraction: (speeds_kmh.size - moving.size).to_f / speeds_kmh.size,
        hints: window_hints(window_rows),
        sparse: dts.any? && (dts.sum.to_f / dts.size) > Emissions::TUNING[:sparse_dt_s],
        point_ids: window_rows.map { |r| r[:point_id] }
      }
    end

    def self.percentile(sorted_values, fraction)
      return nil if sorted_values.empty?

      rank = fraction * (sorted_values.size - 1)
      lower = sorted_values[rank.floor]
      upper = sorted_values[rank.ceil]
      lower + ((upper - lower) * (rank - rank.floor))
    end

    def self.heading_change_rate(rows)
      samples = rows.filter_map do |r|
        next nil if r[:bearing_delta_deg].nil? || r[:dt].nil? || r[:dt] <= 0

        r[:bearing_delta_deg] / r[:dt]
      end
      return nil if samples.empty?

      samples.sum / samples.size
    end

    def self.standard_deviation(values)
      return nil if values.size < 2

      mean = values.sum / values.size
      variance = values.sum { |v| (v - mean)**2 } / (values.size - 1)
      Math.sqrt(variance)
    end

    def self.window_hints(rows)
      totals = Hash.new { |h, k| h[k] = [] }
      rows.each do |row|
        HintScorer.call(row[:motion_data]).each { |mode, value| totals[mode] << value }
      end
      totals.transform_values { |values| values.sum / rows.size }
    end
  end
end
