# frozen_string_literal: true

# Resolves points.country_name (and the legacy points.country string) against
# countries.id, one id-range batch per invocation. Prerequisite for dropping
# country_name in the table rewrite; unmatched names stay NULL and keep
# resolving through Point#country_name's fallback chain.
class DataMigrations::BackfillPointCountryIdJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 50_000
  PAUSE = 5.seconds

  def perform(start_id = nil)
    start_id ||= Point.minimum(:id)
    return if start_id.nil?

    end_id = start_id + BATCH_SIZE - 1

    resolve_country_name(start_id, end_id)
    resolve_legacy_country(start_id, end_id)

    max_id = Point.maximum(:id)
    return if max_id.nil? || end_id >= max_id

    self.class.set(wait: PAUSE).perform_later(end_id + 1)
  end

  private

  def execute_sanitized(sql, *binds)
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array([sql, *binds])
    )
  end

  def resolve_country_name(start_id, end_id)
    execute_sanitized(<<~SQL.squish, start_id, end_id)
      UPDATE points p
      SET country_id = c.id
      FROM countries c
      WHERE p.id BETWEEN ? AND ?
        AND p.country_id IS NULL
        AND p.country_name IS NOT NULL
        AND c.name = p.country_name
    SQL
  end

  def resolve_legacy_country(start_id, end_id)
    execute_sanitized(<<~SQL.squish, start_id, end_id)
      UPDATE points p
      SET country_id = c.id
      FROM countries c
      WHERE p.id BETWEEN ? AND ?
        AND p.country_id IS NULL
        AND p.country_name IS NULL
        AND p.country IS NOT NULL
        AND c.name = p.country
    SQL
  end
end
