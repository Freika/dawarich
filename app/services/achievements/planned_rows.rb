# frozen_string_literal: true

module Achievements
  module PlannedRows
    def self.select(sql)
      connection = ApplicationRecord.connection
      connection.transaction(requires_new: true) do
        original = connection.select_value('SHOW enable_nestloop')
        connection.exec_query('SET LOCAL enable_nestloop = off', 'Achievements plan')
        begin
          connection.select_rows(sql)
        ensure
          connection.exec_query("SET LOCAL enable_nestloop = #{connection.quote(original)}", 'Achievements plan')
        end
      end
    end
  end
end
