# frozen_string_literal: true

module Points
  class Downsampler
    Result = Struct.new(:relation, :total_count, :sampled, keyword_init: true)

    def initialize(relation:, order: 'asc', max_points: 20_000)
      @relation = relation
      @order = order.to_s
      @max_points = max_points.to_i
    end

    def call
      ordered_relation = relation.reorder(timestamp: sql_direction, id: sql_direction)
      total_count = count_rows(ordered_relation)

      return Result.new(relation: ordered_relation, total_count:, sampled: false) if total_count <= max_points

      sampled_ids = sampled_ids_for(ordered_relation, total_count)
      sampled_relation = relation.where(id: sampled_ids).reorder(timestamp: sql_direction, id: sql_direction)

      Result.new(relation: sampled_relation, total_count:, sampled: true)
    end

    private

    attr_reader :relation, :order, :max_points

    def sql_direction
      order == 'desc' ? :desc : :asc
    end

    def count_rows(relation)
      relation.except(:select, :order, :includes, :preload, :eager_load, :limit, :offset).count(:id)
    end

    def sampled_ids_for(relation, total_count)
      return relation.limit(1).pluck(:id) if max_points == 1

      direction = sql_direction.to_s.upcase
      denominator = max_points - 1
      table_name = Point.table_name

      ranked_sql = relation
                   .except(:select, :includes, :preload, :eager_load, :limit, :offset)
                   .select(
                     Arel.sql(
                       "#{table_name}.id AS sampled_id, " \
                       "ROW_NUMBER() OVER (ORDER BY #{table_name}.timestamp #{direction}, " \
                       "#{table_name}.id #{direction}) AS row_num"
                     )
                   )
                   .to_sql

      target_rows_sql = <<~SQL.squish
        SELECT FLOOR(1 + (series_index * (#{total_count} - 1)::float / #{denominator}))::bigint AS row_num
        FROM generate_series(0, #{max_points - 1}) AS series_index
      SQL

      Point.from("(#{ranked_sql}) sampled_points")
           .joins("INNER JOIN (#{target_rows_sql}) target_rows ON target_rows.row_num = sampled_points.row_num")
           .order(Arel.sql('sampled_points.row_num'))
           .limit(max_points)
           .pluck(Arel.sql('sampled_points.sampled_id'))
    end
  end
end
