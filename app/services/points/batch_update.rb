# frozen_string_literal: true

module Points
  module BatchUpdate
    module_function

    def column(name, values_by_id, cast:)
      return 0 if values_by_id.empty?

      connection = ActiveRecord::Base.connection
      rows = values_by_id.map { |id, value| "(#{id.to_i}, #{connection.quote(value)}::#{cast})" }

      connection.exec_update(<<~SQL)
        UPDATE points
        SET #{connection.quote_column_name(name)} = v.value
        FROM (VALUES #{rows.join(', ')}) AS v(id, value)
        WHERE points.id = v.id
      SQL
    end
  end
end
