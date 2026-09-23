# frozen_string_literal: true

module MapMatching
  class Processor
    MAX_POINTS = 10_000
    SCHEMA_VERSION = 1

    Result = Data.define(:status, :path, :data)

    def self.skipped(input)
      new(input).send(:skipped_result)
    end

    def initialize(input, client: Atlas::Client.new)
      @input = input
      @client = client
    end

    def call
      return skipped_result unless input.eligible?

      provider = client.version
      outcomes = input.portions.map { |portion| process(portion) }
      accepted = outcomes.count { |outcome| outcome[:accepted] }
      status = status_for(outcomes, accepted)
      path = Composer.call(outcomes.flat_map { |outcome| outcome[:lines] }) if accepted.positive?

      Result.new(
        status:,
        path:,
        data: diagnostics(provider:, outcomes:)
      )
    end

    private

    attr_reader :input, :client

    def process(portion)
      return fallback(portion, result: 'unsupported') unless portion.eligible?
      return fallback(portion, result: 'rejected', reasons: ['too_many_points']) if portion.points.size > MAX_POINTS

      response = client.map_match(shape: portion.points.map(&:atlas_shape), mode: portion.atlas_mode)
      decision = QualityPolicy.call(
        geometry: response.geometry,
        stats: response.stats,
        input_point_count: portion.points.size
      )

      if decision.accepted?
        accepted(portion, response)
      else
        fallback(portion, result: 'rejected', reasons: decision.reasons, stats: response.stats)
      end
    rescue Atlas::Client::InvalidRequest => e
      fallback(portion, result: 'rejected', reasons: [e.code])
    end

    def accepted(portion, response)
      {
        accepted: true,
        lines: geometry_lines(response.geometry),
        diagnostic: diagnostic(portion, result: 'accepted', stats: response.stats)
      }
    end

    def fallback(portion, result:, reasons: [], stats: {})
      {
        accepted: false,
        lines: [portion.original_coordinates],
        diagnostic: diagnostic(portion, result:, reasons:, stats:)
      }
    end

    def diagnostic(portion, result:, reasons: [], stats: {})
      {
        transportation_mode: portion.transportation_mode,
        atlas_mode: portion.atlas_mode,
        result:,
        reasons:,
        point_count: portion.points.size,
        stats: compact_stats(stats)
      }.compact
    end

    def compact_stats(stats)
      {
        matched: stats['matched'],
        interpolated: stats['interpolated'],
        unmatched: stats['unmatched'],
        segments: stats['segments'],
        mean_distance: stats['mean_distance_from_trace_point'],
        p95_distance: stats['p95_distance_from_trace_point'],
        max_distance: stats['max_distance_from_trace_point'],
        confidence_score: stats['confidence_score'],
        raw_score: stats['raw_score']
      }.compact
    end

    def geometry_lines(geometry)
      geometry['type'] == 'LineString' ? [geometry['coordinates']] : geometry['coordinates']
    end

    def status_for(outcomes, accepted)
      return :rejected if accepted.zero?
      return :matched if outcomes.all? { |outcome| outcome[:accepted] }

      :partial
    end

    def diagnostics(provider:, outcomes:)
      {
        schema_version: SCHEMA_VERSION,
        policy_version: QualityPolicy::VERSION,
        provider: { name: 'atlas', version: provider[:version], revision: provider[:revision] }.compact,
        segments: outcomes.map { |outcome| outcome[:diagnostic] },
        error: nil
      }
    end

    def skipped_result
      Result.new(
        status: :skipped,
        path: nil,
        data: {
          schema_version: SCHEMA_VERSION,
          policy_version: QualityPolicy::VERSION,
          provider: { name: 'atlas' },
          segments: input.portions.map do |portion|
            diagnostic(portion, result: 'unsupported')
          end,
          error: nil
        }
      )
    end
  end
end
