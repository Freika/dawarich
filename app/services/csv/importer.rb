# frozen_string_literal: true

require 'csv'

module Csv
  class Importer
    include Imports::Broadcaster
    include Imports::BulkInsertable
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
      detection = Csv::Detector.new(resolved_path).call
      points_data = []
      skipped = 0
      header_skipped = false

      File.foreach(resolved_path, encoding: 'bom|utf-8') do |raw_line|
        line = raw_line.strip
        next if line.empty?

        unless header_skipped
          header_skipped = true
          next
        end

        row = CSV.parse_line(line, col_sep: detection[:delimiter])
        point = Csv::Params.new(row, detection, user_id, import.id).call

        if point
          points_data << point
        else
          skipped += 1
          Rails.logger.warn("CSV import #{import.id}: skipped row")
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

    def importer_name
      'CSV'
    end
  end
end
