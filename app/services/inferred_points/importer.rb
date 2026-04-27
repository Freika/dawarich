# frozen_string_literal: true

module InferredPoints
  # Persists inferred points as a completed import and regenerates the tracks
  # covering them. Inferred points land inside an existing track's span, so we do
  # a full bulk rebuild (untracked_only: false) of the affected window. This
  # discards any manual transit-mode corrections in that window, matching
  # Users::RecalculateDataJob behavior.
  class Importer
    def initialize(user:, points:, geojson:, import_name:, filename_prefix:)
      @user = user
      @points = points
      @geojson = geojson
      @import_name = import_name
      @filename_prefix = filename_prefix
    end

    def call
      return if points.empty?

      Point.transaction do
        @import = user.imports.create!(
          name: import_name,
          source: :geojson,
          status: :completed,
          skip_background_processing: true
        )

        @import.file.attach(
          io: StringIO.new(geojson),
          filename: "#{filename_prefix}_#{@import.id}.geojson",
          content_type: 'application/json'
        )

        points.each do |point|
          point.import = @import
          point.save!
        end

        @import.update_columns(points_count: points.size, processed: points.size)
      end

      enqueue_regeneration
      @import
    end

    private

    attr_reader :user, :points, :geojson, :import_name, :filename_prefix

    def enqueue_regeneration
      lo, hi = points.map(&:timestamp).minmax
      window_lo = Time.zone.at(lo)
      window_hi = Time.zone.at(hi)

      # Bulk rebuild deletes whole overlapping tracks, but only covers the window
      # +/- TimeChunker's buffer. Expand to each overlapping track's full extent so
      # a long track can't be truncated by the rebuild.
      overlapping = user.tracks.where('(start_at, end_at) OVERLAPS (?, ?)', window_lo, window_hi)
      start_at = [window_lo, overlapping.minimum(:start_at)].compact.min
      end_at = [window_hi, overlapping.maximum(:end_at)].compact.max

      Tracks::ParallelGeneratorJob.perform_later(
        user.id,
        start_at: start_at,
        end_at: end_at,
        mode: :bulk,
        untracked_only: false
      )
    end
  end
end
