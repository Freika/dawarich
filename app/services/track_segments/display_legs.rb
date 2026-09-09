# frozen_string_literal: true

module TrackSegments
  # Condenses a track's time-anchored segments into the simplified list shown
  # at the first expansion level of the timeline: real legs, stops, one chip
  # per run of micro-segments, and unclaimed "moving" stretches where the
  # posterior is too weak to assert a mode. Returns nil when segments are not
  # time-anchored (legacy index rows) or contain no movement — callers fall
  # back to the raw segment list.
  class DisplayLegs
    UNCERTAIN_BELOW = 0.6
    SHORT_LEG_S = 300
    STOP_GAP_S = 240

    # segment_id is present only when the item maps to exactly one segment —
    # a merged transfer spans several and an inferred stop has none, so
    # neither can be edited as a single unit.
    Item = Struct.new(:kind, :mode, :distance, :duration, :segment_count, :segment_id, keyword_init: true)
    Span = Struct.new(:kind, :mode, :percent, keyword_init: true)
    Result = Struct.new(:items, :spans, keyword_init: true)

    def self.call(segments)
      new(segments).call
    end

    def initialize(segments)
      @raw = segments.to_a
    end

    def call
      return nil if @raw.empty?
      return nil unless @raw.all? { |s| s.start_at && s.end_at }

      @segments = @raw.sort_by(&:start_at)
      moving = @segments.reject { |s| s.transportation_mode == 'stationary' }
      return nil if moving.empty?

      units = group_short_runs(moving.map { |s| build_unit(s) })
      Result.new(items: interleave_stops(units), spans: build_spans(units))
    end

    private

    attr_reader :segments

    def build_unit(segment)
      corrected = segment.corrected_at.present?
      uncertain = !corrected &&
                  (segment.transportation_mode == 'unknown' ||
                   (segment.confidence_score && segment.confidence_score < UNCERTAIN_BELOW))

      {
        kind: uncertain ? :uncertain : :leg,
        mode: uncertain ? nil : segment.transportation_mode,
        segment_id: segment.id,
        distance: segment.distance.to_i,
        duration: segment.duration.to_i,
        start_at: segment.start_at,
        end_at: segment.end_at,
        short: !corrected && segment.duration.to_i < SHORT_LEG_S
      }
    end

    # Runs of >= 2 consecutive short segments (parking, walking to the door)
    # merge into one neutral transfer chip; an isolated short segment is
    # information and stays a leg.
    def group_short_runs(units)
      grouped = []
      run = []

      flush = lambda do
        run.size >= 2 ? grouped << merge_run(run) : grouped.concat(run)
        run = []
      end

      units.each do |unit|
        if unit[:short] && (run.empty? || (unit[:start_at] - run.last[:end_at]) < STOP_GAP_S)
          run << unit
        else
          flush.call
          unit[:short] ? run << unit : grouped << unit
        end
      end
      flush.call

      grouped
    end

    def merge_run(run)
      {
        kind: :transfer,
        mode: nil,
        distance: run.sum { |u| u[:distance] },
        duration: (run.last[:end_at] - run.first[:start_at]).round,
        segment_count: run.size,
        start_at: run.first[:start_at],
        end_at: run.last[:end_at]
      }
    end

    def interleave_stops(units)
      items = []

      units.each_with_index do |unit, index|
        if index.positive?
          gap = (unit[:start_at] - units[index - 1][:end_at]).round
          items << Item.new(kind: :stop, duration: gap) if gap >= STOP_GAP_S
        end
        items << Item.new(kind: unit[:kind], mode: unit[:mode], distance: unit[:distance],
                          duration: unit[:duration], segment_count: unit[:segment_count],
                          segment_id: unit[:segment_id])
      end

      items
    end

    def build_spans(units)
      total = (segments.last.end_at - segments.first.start_at).to_f
      return [] if total <= 0

      spans = []
      cursor = segments.first.start_at

      units.each do |unit|
        gap = unit[:start_at] - cursor
        spans << Span.new(kind: :gap, percent: percent_of(gap, total)) if gap.positive?
        spans << Span.new(kind: unit[:kind] == :leg ? :mode : :uncertain, mode: unit[:mode],
                          percent: percent_of(unit[:end_at] - unit[:start_at], total))
        cursor = unit[:end_at]
      end

      tail = segments.last.end_at - cursor
      spans << Span.new(kind: :gap, percent: percent_of(tail, total)) if tail.positive?

      spans
    end

    def percent_of(seconds, total)
      (seconds / total * 100).round(1)
    end
  end
end
