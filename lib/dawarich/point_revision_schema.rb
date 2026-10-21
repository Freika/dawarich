# frozen_string_literal: true

module Dawarich
  module PointRevisionSchema
    private

    def tables(stream)
      super
      return unless @connection.table_exists?('point_revisions')

      functions = @connection.select_values(<<~SQL)
        SELECT pg_get_functiondef(p.oid) FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = current_schema()
          AND p.proname IN ('points_revision_insert', 'points_revision_update', 'points_revision_delete', 'points_revision_truncate')
        ORDER BY p.proname
      SQL
      triggers = @connection.select_values(<<~SQL)
        SELECT pg_get_triggerdef(oid) FROM pg_trigger
        WHERE tgrelid = 'points'::regclass
          AND tgname IN ('points_revision_insert', 'points_revision_update', 'points_revision_delete', 'points_revision_truncate')
        ORDER BY tgname
      SQL
      (functions + triggers).each do |sql|
        stream.puts "  execute <<~SQL\n#{sql.indent(4)}\n  SQL\n"
      end
    end
  end
end
