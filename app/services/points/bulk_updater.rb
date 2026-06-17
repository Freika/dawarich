# frozen_string_literal: true

module Points
  class BulkUpdater
    def self.call(rows, columns)
      new(rows, columns).call
    end

    def initialize(rows, columns)
      @rows = rows
      @columns = columns.map(&:to_sym)
    end

    def call
      return 0 if @rows.empty?

      connection.exec_update(update_sql)
    end

    private

    attr_reader :rows, :columns

    def connection
      Point.connection
    end

    def all_columns
      [:id, *columns]
    end

    def update_sql
      <<~SQL.squish
        UPDATE points AS p
        SET #{set_clause}
        FROM (VALUES #{values_list}) AS v (#{column_list})
        WHERE p.id = v.id
      SQL
    end

    def set_clause
      columns.map { |column| "#{quote_column(column)} = v.#{quote_column(column)}" }.join(', ')
    end

    def column_list
      all_columns.map { |column| quote_column(column) }.join(', ')
    end

    def values_list
      rows.map { |row| "(#{tuple(row)})" }.join(', ')
    end

    def tuple(row)
      all_columns.map { |column| cast_value(row[column], column) }.join(', ')
    end

    def cast_value(value, column)
      serialized = Point.type_for_attribute(column.to_s).serialize(value)

      "#{connection.quote(serialized)}::#{sql_type(column)}"
    end

    def sql_type(column)
      Point.columns_hash[column.to_s].sql_type
    end

    def quote_column(column)
      connection.quote_column_name(column)
    end
  end
end
