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
      step = (total_count.to_f / max_points).ceil
      direction = sql_direction.to_s.upcase

      ranked_sql = relation
                   .except(:select, :includes, :preload, :eager_load, :limit, :offset)
                   .select(
                     Arel.sql(
                       "#{Point.table_name}.id AS sampled_id, " \
                       "ROW_NUMBER() OVER (ORDER BY #{Point.table_name}.timestamp #{direction}, " \
                       "#{Point.table_name}.id #{direction}) AS row_num"
                     )
                   )
                   .to_sql

      Point.from("(#{ranked_sql}) sampled_points")
           .where('((row_num - 1) % ?) = 0', step)
           .limit(max_points)
           .pluck(Arel.sql('sampled_points.sampled_id'))
    end
  end
end
