# frozen_string_literal: true

module FixtureCleanup
  def self.delete!(tables)
    connection = ActiveRecord::Base.connection
    names = tables.map { connection.quote(_1) }.join(', ')
    ordered = connection.select_values(<<~SQL)
      WITH RECURSIVE dependents(oid, path) AS (
        SELECT name::regclass::oid, ARRAY[name::regclass::oid]
        FROM unnest(ARRAY[#{names}]) AS name
        UNION ALL
        SELECT fk.conrelid, d.path || fk.conrelid
        FROM dependents d JOIN pg_constraint fk ON fk.confrelid = d.oid
        WHERE fk.contype = 'f' AND NOT fk.conrelid = ANY(d.path)
      )
      SELECT oid::regclass::text FROM dependents
      GROUP BY oid ORDER BY max(cardinality(path)) DESC, oid
    SQL
    connection.transaction { ordered.each { connection.execute("DELETE FROM #{_1}") } }
  end
end
