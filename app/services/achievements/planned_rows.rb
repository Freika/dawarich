# frozen_string_literal: true

module Achievements
  module PlannedRows
    STATEMENT_TIMEOUT = '10min'

    # On error the savepoint rollback undoes SET LOCAL, so settings are restored only on success.
    def self.select(sql)
      connection = ApplicationRecord.connection
      connection.transaction(requires_new: true) do
        settings = { 'enable_nestloop' => 'off', 'statement_timeout' => STATEMENT_TIMEOUT }
        originals = settings.keys.index_with { |name| connection.select_value("SHOW #{name}") }
        apply(connection, settings)
        rows = connection.select_rows(sql)
        apply(connection, originals)
        rows
      end
    end

    def self.apply(connection, settings)
      settings.each do |name, value|
        connection.exec_query("SET LOCAL #{name} = #{connection.quote(value)}", 'Achievements plan')
      end
    end
    private_class_method :apply
  end
end
