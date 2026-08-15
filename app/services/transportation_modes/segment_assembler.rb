# frozen_string_literal: true

module TransportationModes
  # Turns decoded windows into time-anchored segment hashes ready for
  # TrackSegments::BulkInserter. Manually corrected segments are preserved by
  # subtracting their time ranges from the auto output.
  class SegmentAssembler
    def self.call(rows:, windows:, decoded:, preserved: [])
      new(rows, windows, decoded, preserved).call
    end

    def initialize(rows, windows, decoded, preserved)
      @rows = rows
      @windows = windows
      @decoded = decoded
      @preserved = preserved
    end

    def call
      return [] if @windows.empty? || @rows.empty?

      runs = merge_runs(window_intervals)
      segments = runs.flat_map { |run| clip_around_preserved(run) }
                     .filter_map { |run| build_segment(run) }
      enforce_invariants(segments)
    end

    private

    # Each window owns [start_ts, next window start) within its chain; the
    # last window of a chain extends to the last point before the gap (or the
    # end of the track), covering the sub-step tail the Windower leaves.
    def window_intervals
      @windows.each_with_index.map do |window, i|
        next_window = @windows[i + 1]
        interval_end = if next_window.nil?
                         @rows.last[:ts]
                       elsif next_window[:gap_before]
                         last_row_ts_before(next_window[:start_ts])
                       else
                         next_window[:start_ts]
                       end
        { start_ts: window[:start_ts], end_ts: interval_end,
          mode: @decoded[i][:mode], posterior: @decoded[i][:posterior],
          hinted: @windows[i][:hints].present?, gap_before: window[:gap_before] }
      end
    end

    def last_row_ts_before(cutoff_ts)
      row = @rows.reverse_each.find { |r| r[:ts] < cutoff_ts }
      row ? row[:ts] : cutoff_ts
    end

    def merge_runs(intervals)
      runs = []
      intervals.each do |interval|
        current = runs.last
        if current && current[:mode] == interval[:mode] && !interval[:gap_before]
          current[:end_ts] = interval[:end_ts]
          current[:posteriors] << interval[:posterior]
          current[:hinted] ||= interval[:hinted]
        else
          runs << { mode: interval[:mode], start_ts: interval[:start_ts],
                    end_ts: interval[:end_ts], posteriors: [interval[:posterior]],
                    hinted: interval[:hinted] }
        end
      end
      runs
    end

    def preserved_ranges
      @preserved_ranges ||= @preserved.filter_map do |segment|
        next nil if segment.start_at.nil? || segment.end_at.nil?

        [segment.start_at.to_i, segment.end_at.to_i]
      end.sort_by(&:first)
    end

    def clip_around_preserved(run)
      pieces = [run.dup]
      preserved_ranges.each do |p_start, p_end|
        pieces = pieces.flat_map do |piece|
          subtract_range(piece, p_start, p_end)
        end
      end
      pieces.select { |p| (p[:end_ts] - p[:start_ts]) >= Emissions::TUNING[:min_auto_sliver_s] }
    end

    def subtract_range(piece, p_start, p_end)
      return [piece] if p_end <= piece[:start_ts] || p_start >= piece[:end_ts]

      result = []
      result << piece.merge(end_ts: p_start) if p_start > piece[:start_ts]
      result << piece.merge(start_ts: p_end) if p_end < piece[:end_ts]
      result
    end

    def build_segment(run)
      segment_rows = @rows.select { |r| r[:ts] >= run[:start_ts] && r[:ts] <= run[:end_ts] }
      return nil if segment_rows.size < 2

      start_ts = segment_rows.first[:ts]
      end_ts = segment_rows.last[:ts]
      return nil if (end_ts - start_ts) < Emissions::TUNING[:min_auto_sliver_s]

      distance = segment_rows.drop(1).sum { |r| r[:dist_m] || 0.0 }
      duration = end_ts - start_ts
      posterior = run[:posteriors].sum / run[:posteriors].size

      {
        mode: run[:mode],
        start_at: Time.zone.at(start_ts), end_at: Time.zone.at(end_ts),
        path_wkt: linestring_wkt(segment_rows),
        distance: distance.round, duration: duration,
        avg_speed: duration.positive? ? ((distance / duration) * 3.6).round(2) : 0.0,
        max_speed: max_speed_kmh(segment_rows),
        confidence: confidence_bucket(posterior),
        confidence_score: posterior.round(4),
        source: run[:hinted] ? 'hints+inferred' : 'inferred'
      }
    end

    def linestring_wkt(segment_rows)
      coords = segment_rows.filter_map do |r|
        "#{r[:lon]} #{r[:lat]}" if r[:lon] && r[:lat]
      end
      return nil if coords.size < 2

      "LINESTRING(#{coords.join(', ')})"
    end

    def max_speed_kmh(segment_rows)
      speeds = segment_rows.select { |r| r[:speed_valid] }.map { |r| r[:speed_mps] * 3.6 }
      speeds.max&.round(2)
    end

    def confidence_bucket(posterior)
      return :high if posterior > Emissions::TUNING[:confidence_high]
      return :low if posterior < Emissions::TUNING[:confidence_low]

      :medium
    end

    def enforce_invariants(segments)
      sorted = segments.sort_by { |s| s[:start_at] }
      sorted.each_cons(2) do |a, b|
        next if a[:end_at] <= b[:start_at]

        message = "[TransportationModes] overlapping segments #{a[:mode]}/#{b[:mode]}"
        raise message if Rails.env.test?

        Rails.logger.warn(message)
        b[:start_at] = a[:end_at]
      end
      sorted.reject { |s| s[:end_at] <= s[:start_at] }
    end
  end
end
