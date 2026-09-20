# frozen_string_literal: true

module Maps
  class BoundsCalculator
    class NoUserFoundError < StandardError; end
    class NoDateRangeError < StandardError; end

    MIN_OUTLIER_POINTS = 50
    MIN_DENSE_CELL_POINTS = 2
    CELL_SIZE_DEGREES = 2
    OUTLIER_GAP_RATIO = 0.2
    MIN_OUTLIER_GAP_DEGREES = 1
    ROBUST_QUERY_TIMEOUT_MS = 5000
    SAMPLE_QUERY_TIMEOUT_MS = 2000
    SAMPLE_MARKS = 1024

    def initialize(user:, start_date:, end_date:, import_id: nil, robust: false, respect_plan_scope: true)
      @user = user
      @start_date = start_date
      @end_date = end_date
      @import_id = import_id.presence
      @robust = robust
      @respect_plan_scope = respect_plan_scope
    end

    def call
      validate_inputs!

      start_timestamp = parse_date_parameter(@start_date)
      end_timestamp = parse_date_parameter(@end_date)

      unless @robust
        bounds_result = execute_exact_bounds_query(start_timestamp, end_timestamp)
        point_count = bounds_result['point_count'].to_i

        return build_no_data_response if point_count.zero?

        return build_success_response(bounds_result.transform_values(&:to_f).transform_keys(&:to_sym), point_count)
      end

      approximate = false
      cells = begin
        execute_cell_bounds_query(start_timestamp, end_timestamp)
      rescue ActiveRecord::QueryCanceled
        approximate = true
        execute_sampled_cell_bounds_query(start_timestamp, end_timestamp)
      end
      point_count = cells.sum { |cell| cell['point_count'].to_i }

      return build_no_data_response if point_count.zero?

      build_success_response(bounds_for(inlier_cells(cells, point_count)), approximate ? nil : point_count,
                             approximate:)
    end

    private

    def validate_inputs!
      raise NoUserFoundError, I18n.t('services.maps.bounds_calculator.no_user') unless @user
      raise NoDateRangeError, I18n.t('services.maps.bounds_calculator.no_date_range') unless @start_date && @end_date
    end

    def scoped_points(start_timestamp, end_timestamp)
      points = @respect_plan_scope ? @user.scoped_points : @user.points
      scope = points.without_raw_data.not_anomaly.where(timestamp: start_timestamp..end_timestamp)
      @import_id ? scope.where(import_id: @import_id) : scope
    end

    def execute_exact_bounds_query(start_timestamp, end_timestamp)
      scope = scoped_points(start_timestamp, end_timestamp)

      ActiveRecord::Base.connection.select_one(<<~SQL.squish)
        SELECT COUNT(*) AS point_count,
               ST_YMin(ST_Extent(point_lonlat::geometry)) AS min_lat,
               ST_YMax(ST_Extent(point_lonlat::geometry)) AS max_lat,
               ST_XMin(ST_Extent(point_lonlat::geometry)) AS min_lng,
               ST_XMax(ST_Extent(point_lonlat::geometry)) AS max_lng
        FROM (#{scope.reselect('points.lonlat AS point_lonlat').to_sql}) bounds_points
      SQL
    end

    def execute_cell_bounds_query(start_timestamp, end_timestamp)
      scope = scoped_points(start_timestamp, end_timestamp).where.not(lonlat: nil)

      select_cells_with_timeout(ROBUST_QUERY_TIMEOUT_MS, <<~SQL.squish)
        SELECT FLOOR(lng / #{CELL_SIZE_DEGREES}) AS lng_cell,
               FLOOR(lat / #{CELL_SIZE_DEGREES}) AS lat_cell,
               COUNT(*) AS point_count,
               MIN(lat) AS min_lat, MAX(lat) AS max_lat,
               MIN(lng) AS min_lng, MAX(lng) AS max_lng
        FROM (
          SELECT ST_X(point_lonlat::geometry) AS lng,
                 ST_Y(point_lonlat::geometry) AS lat
          FROM (#{scope.reselect('points.lonlat AS point_lonlat').to_sql}) bounds_points
        ) coordinates
        GROUP BY 1, 2
      SQL
    end

    def execute_sampled_cell_bounds_query(start_timestamp, end_timestamp)
      scope = scoped_points(start_timestamp, end_timestamp).where.not(lonlat: nil)
      columns = 'points.id AS point_id, points.timestamp AS point_timestamp, points.lonlat AS point_lonlat'
      scoped_sql = scope.reselect(columns).to_sql

      select_cells_with_timeout(SAMPLE_QUERY_TIMEOUT_MS, <<~SQL.squish)
        WITH occupied_range AS (
          SELECT
            (SELECT point_timestamp FROM (#{scoped_sql}) earliest
             ORDER BY point_timestamp LIMIT 1) AS first_timestamp,
            (SELECT point_timestamp FROM (#{scoped_sql}) latest
             ORDER BY point_timestamp DESC LIMIT 1) AS last_timestamp
        ), sampled_points AS (
          SELECT DISTINCT ON (sample.point_id) sample.point_id, sample.point_lonlat
          FROM occupied_range
          CROSS JOIN generate_series(0, #{SAMPLE_MARKS - 1}) AS marks(sample_number)
          JOIN LATERAL (
            SELECT point_id, point_lonlat
            FROM (#{scoped_sql}) scoped
            WHERE point_timestamp >= occupied_range.first_timestamp +
              ((occupied_range.last_timestamp - occupied_range.first_timestamp)::bigint *
               marks.sample_number / #{SAMPLE_MARKS - 1})
            ORDER BY point_timestamp, point_id
            LIMIT 1
          ) sample ON true
        ), coordinates AS (
          SELECT ST_X(point_lonlat::geometry) AS lng,
                 ST_Y(point_lonlat::geometry) AS lat
          FROM sampled_points
        )
        SELECT FLOOR(lng / #{CELL_SIZE_DEGREES}) AS lng_cell,
               FLOOR(lat / #{CELL_SIZE_DEGREES}) AS lat_cell,
               COUNT(*) AS point_count,
               MIN(lat) AS min_lat, MAX(lat) AS max_lat,
               MIN(lng) AS min_lng, MAX(lng) AS max_lng
        FROM coordinates
        GROUP BY 1, 2
      SQL
    end

    def select_cells_with_timeout(timeout_ms, sql)
      connection = ActiveRecord::Base.connection
      connection.transaction do
        connection.execute("SET LOCAL statement_timeout = #{timeout_ms}")
        connection.select_all(sql)
      end
    end

    def inlier_cells(cells, point_count)
      return cells if point_count < MIN_OUTLIER_POINTS

      supported_cells = connected_cells_with_minimum_points(cells)
      return cells if supported_cells.empty?

      supported_keys = supported_cells.index_by { |cell| cell_key(cell) }
      dense_bounds = bounds_for(supported_cells)
      full_bounds = bounds_for(cells)
      lng_gap = [MIN_OUTLIER_GAP_DEGREES, (full_bounds[:max_lng] - full_bounds[:min_lng]) * OUTLIER_GAP_RATIO].max
      lat_gap = [MIN_OUTLIER_GAP_DEGREES, (full_bounds[:max_lat] - full_bounds[:min_lat]) * OUTLIER_GAP_RATIO].max

      cells.select do |cell|
        supported_keys.key?(cell_key(cell)) ||
          (cell['min_lng'].to_f <= dense_bounds[:max_lng] + lng_gap &&
           cell['max_lng'].to_f >= dense_bounds[:min_lng] - lng_gap &&
           cell['min_lat'].to_f <= dense_bounds[:max_lat] + lat_gap &&
           cell['max_lat'].to_f >= dense_bounds[:min_lat] - lat_gap)
      end
    end

    def connected_cells_with_minimum_points(cells)
      by_key = cells.index_by { |cell| cell_key(cell) }
      visited = {}
      supported = []

      cells.each do |cell|
        next if visited[cell_key(cell)]

        component = []
        pending = [cell]
        while (current = pending.pop)
          key = cell_key(current)
          next if visited[key]

          visited[key] = true
          component << current
          (-1..1).each do |lng_offset|
            (-1..1).each do |lat_offset|
              neighbor = by_key[[key[0] + lng_offset, key[1] + lat_offset]]
              pending << neighbor if neighbor && !visited[cell_key(neighbor)]
            end
          end
        end
        supported.concat(component) if component.sum { |member| member['point_count'].to_i } >= MIN_DENSE_CELL_POINTS
      end

      supported
    end

    def cell_key(cell)
      [cell['lng_cell'].to_i, cell['lat_cell'].to_i]
    end

    def bounds_for(cells)
      {
        min_lat: cells.map { |cell| cell['min_lat'].to_f }.min,
        max_lat: cells.map { |cell| cell['max_lat'].to_f }.max,
        min_lng: cells.map { |cell| cell['min_lng'].to_f }.min,
        max_lng: cells.map { |cell| cell['max_lng'].to_f }.max
      }
    end

    def build_success_response(bounds_result, point_count, approximate: false)
      data = {
        min_lat: bounds_result[:min_lat],
        max_lat: bounds_result[:max_lat],
        min_lng: bounds_result[:min_lng],
        max_lng: bounds_result[:max_lng],
        point_count: point_count
      }
      data[:approximate] = true if approximate

      {
        success: true,
        data: data
      }
    end

    def build_no_data_response
      {
        success: false,
        error: I18n.t('services.maps.bounds_calculator.no_data_found_for_the_specified_date_range'),
        point_count: 0
      }
    end

    def parse_date_parameter(param)
      case param
      when String
        if param.match?(/^\d+$/)
          param.to_i
        else
          parsed_time = Time.zone.parse(param)
          raise ArgumentError, I18n.t('services.maps.bounds_calculator.invalid_date', value: param) if parsed_time.nil?

          parsed_time.to_i
        end
      when Integer
        param
      else
        param.to_i
      end
    rescue ArgumentError => e
      Rails.logger.error "Invalid date format: #{param} - #{e.message}"
      raise ArgumentError, I18n.t('services.maps.bounds_calculator.invalid_date', value: param)
    end
  end
end
