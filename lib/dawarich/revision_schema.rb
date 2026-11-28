# frozen_string_literal: true

module Dawarich
  module RevisionSchema
    REVISIONS = {
      'point_revisions' => %w[points points_revision],
      'track_revisions' => %w[tracks tracks_revision]
    }.freeze
    EVENTS = %w[delete insert truncate update].freeze

    private

    def tables(stream)
      super
      REVISIONS.each do |revisions_table, (table, prefix)|
        next unless @connection.table_exists?(revisions_table)

        names = EVENTS.map { |event| @connection.quote("#{prefix}_#{event}") }.join(', ')
        functions = @connection.select_values(<<~SQL)
          SELECT pg_get_functiondef(p.oid) FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = current_schema() AND p.proname IN (#{names})
          ORDER BY p.proname
        SQL
        triggers = @connection.select_values(<<~SQL)
          SELECT pg_get_triggerdef(oid) FROM pg_trigger
          WHERE tgrelid = #{@connection.quote(table)}::regclass AND tgname IN (#{names})
          ORDER BY tgname
        SQL
        (functions + triggers).each { |sql| stream.puts "  execute <<~SQL\n#{sql.indent(4)}\n  SQL\n" }
      end
    end
  end
end
