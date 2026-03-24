# frozen_string_literal: true

require 'csv'

module Csv
  class Importer
    include Imports::Broadcaster
    include Imports::FileLoader

    BATCH_SIZE = 1000

    attr_reader :import, :user_id, :file_path

    def initialize(import, user_id, file_path = nil)
      @import = import
      @user_id = user_id
      @file_path = file_path
    end

    def call
      resolved_path = resolve_file_path
      content = File.read(resolved_path, encoding: 'bom|utf-8')
      lines = content.lines.map(&:strip).reject(&:empty?)
      return if lines.size < 2

      detection = Csv::Detector.new(resolved_path).call
      points_data = []
      skipped = 0

      lines[1..].each_with_index do |line, idx|
        row = CSV.parse_line(line, col_sep: detection[:delimiter])
        point = Csv::Params.new(row, detection, user_id, import.id).call

        if point
          points_data << point
        else
          skipped += 1
          Rails.logger.warn("CSV import #{import.id}: skipped row #{idx + 2}")
        end

        next unless points_data.size >= BATCH_SIZE

        bulk_insert_points(points_data)
        broadcast_import_progress(import, points_data.size)
        points_data = []
      end

      bulk_insert_points(points_data) if points_data.any?
      import.update(raw_data: (import.raw_data || {}).merge('skipped_rows' => skipped))
    ensure
      cleanup_temp_file
    end

    private

    def resolve_file_path
      return file_path if file_path && File.exist?(file_path)

      @temp_file_path = Imports::SecureFileDownloader.new(import.file).download_to_temp_file
    end

    def cleanup_temp_file
      return unless @temp_file_path

      File.delete(@temp_file_path) if File.exist?(@temp_file_path)
    rescue StandardError => e
      Rails.logger.warn("Failed to cleanup CSV temp file: #{e.message}")
    end

    def bulk_insert_points(batch)
      return if batch.empty?

      unique_batch = batch.uniq { |record| [record[:lonlat], record[:timestamp], record[:user_id]] }

      Point.upsert_all(
        unique_batch,
        unique_by: %i[lonlat timestamp user_id],
        returning: false,
        on_duplicate: :skip
      )
    rescue StandardError => e
      create_notification("Failed to process CSV batch: #{e.message}")
    end

    def create_notification(message)
      Notification.create!(
        user_id: user_id,
        title: 'CSV Import Error',
        content: message,
        kind: :error
      )
    end
  end
end
