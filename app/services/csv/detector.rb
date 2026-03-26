# frozen_string_literal: true

require 'csv'

module Csv
  class Detector
    include Imports::FieldAliases

    class DetectionError < StandardError; end

    CANDIDATE_DELIMITERS = [',', ';', "\t"].freeze
    SAMPLE_LINES = 12
    DATA_SAMPLE_SIZE = 10
    DIRECTIONAL_PATTERN = /[NSEW]\z/i
    E7_THRESHOLD = 1_000_000
    UNIX_SECONDS_PATTERN = /\A\d{10}\z/
    UNIX_MILLIS_PATTERN = /\A\d{13}\z/

    def initialize(file_path)
      @file_path = file_path
    end

    def call
      lines = read_sample_lines
      delimiter = detect_delimiter(lines)
      headers = parse_headers(lines.first, delimiter)
      columns = map_columns(headers)
      validate_columns!(columns)

      data_rows = parse_data_rows(lines[1..], delimiter)

      {
        delimiter: delimiter,
        columns: columns,
        coordinate_format: detect_coordinate_format(data_rows, columns),
        timestamp_format: detect_timestamp_format(data_rows, columns),
        comma_decimals: detect_comma_decimals(data_rows, columns, delimiter)
      }
    end

    private

    def read_sample_lines
      File.foreach(@file_path, encoding: 'bom|utf-8', chomp: true)
          .lazy
          .reject(&:empty?)
          .first(SAMPLE_LINES)
    end

    def detect_delimiter(lines)
      sample = lines.first(5)

      CANDIDATE_DELIMITERS.max_by do |delim|
        counts = sample.map { |line| line.count(delim) }
        next -1 if counts.any?(&:zero?)

        counts.uniq.length == 1 ? counts.first : -1
      end
    end

    def parse_headers(header_line, delimiter)
      CSV.parse_line(header_line, col_sep: delimiter)&.map(&:strip) || []
    end

    def map_columns(headers)
      columns = {}

      %i[latitude longitude timestamp altitude speed accuracy
         vertical_accuracy battery heading tracker_id].each do |field|
        idx = find_header(headers, field)
        columns[field] = idx if idx
      end

      # Fallback: substring matching for non-standard headers like "LATITUDE N/S"
      columns[:latitude]  ||= find_header_by_substring(headers, 'latitude')
      columns[:longitude] ||= find_header_by_substring(headers, 'longitude')
      columns[:timestamp] ||= find_header_by_substring(headers, 'timestamp')

      columns
    end

    def find_header_by_substring(headers, keyword)
      normalized = headers.map { |h| h.to_s.downcase.strip }
      normalized.index { |h| h.include?(keyword) }
    end

    def validate_columns!(columns)
      missing = %i[latitude longitude timestamp].reject { |f| columns[f] }
      return if missing.empty?

      raise DetectionError,
            'Could not detect required columns: latitude, longitude, timestamp. ' \
            'Found headers must include recognized aliases for all three.'
    end

    def parse_data_rows(lines, delimiter)
      lines.first(DATA_SAMPLE_SIZE).filter_map do |line|
        CSV.parse_line(line, col_sep: delimiter)&.map(&:strip)
      end
    end

    def detect_coordinate_format(data_rows, columns)
      lat_idx = columns[:latitude]
      lon_idx = columns[:longitude]
      return :decimal_degrees unless lat_idx && lon_idx

      lat_values = data_rows.filter_map { |row| row[lat_idx] }
      lon_values = data_rows.filter_map { |row| row[lon_idx] }
      all_coords = lat_values + lon_values

      return :decimal_degrees if all_coords.empty?

      if all_coords.any? { |v| v.match?(DIRECTIONAL_PATTERN) }
        :directional
      elsif all_coords.all? { |v| v.match?(/\A-?\d+\z/) && v.to_i.abs > E7_THRESHOLD }
        :e7
      else
        :decimal_degrees
      end
    end

    def detect_timestamp_format(data_rows, columns)
      ts_idx = columns[:timestamp]
      return :iso8601 unless ts_idx

      ts_values = data_rows.filter_map { |row| row[ts_idx] }
      return :iso8601 if ts_values.empty?

      if ts_values.all? { |v| v.match?(UNIX_SECONDS_PATTERN) }
        :unix_seconds
      elsif ts_values.all? { |v| v.match?(UNIX_MILLIS_PATTERN) }
        :unix_milliseconds
      else
        :iso8601
      end
    end

    def detect_comma_decimals(data_rows, columns, delimiter)
      return false unless delimiter == ';'

      lat_idx = columns[:latitude]
      lon_idx = columns[:longitude]
      return false unless lat_idx && lon_idx

      coord_values = data_rows.flat_map { |row| [row[lat_idx], row[lon_idx]] }.compact
      return false if coord_values.empty?

      comma_count = coord_values.count { |v| v.include?(',') }
      comma_count > coord_values.length / 2
    end
  end
end
