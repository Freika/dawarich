# frozen_string_literal: true

module Points
  # Resolves point_sources.id for rows about to be inserted, so ingest
  # dual-writes the dimension FK alongside the legacy columns.
  #
  # The digest is computed in SQL, by the very same PointSource.digest_sql
  # expression the backfill uses. Recomputing them in Ruby would be a second implementation of a value
  # that must match byte for byte forever: jsonb normalises key order and
  # spacing, integer-backed enums serialise as numbers rather than labels, and
  # the array columns default to `{}` rather than NULL. Any of those drifting
  # would silently create a parallel set of dimension rows that never match the
  # backfilled ones.
  class DimensionResolver
    # Columns whose value must be present on every row handed to upsert_all:
    # the writer requires a uniform key set across the batch.
    def initialize
      @source_cache = {}
    end

    # Returns rows with :source_id filled in. A no-op until the column exists — 20260816150000 can defer its ALTER to
    # DataMigrations::AddPointDimensionColumnsJob on a busy instance, and ingest
    # must keep working in that window.
    def stamp(rows)
      return rows unless self.class.columns_available?

      rows.each do |row|
        row[:source_id] = source_id_for(row)
        strip_combo_keys(row)
      end
    end

    # The combo lives on the dimension only: leaving the keys in the hash
    # would crash the upsert now that the legacy columns are gone.
    COMBO_KEYS = PointSource::COMBO_COLUMNS.flat_map { |c| [c, c.to_sym] }.freeze

    def strip_combo_keys(row)
      COMBO_KEYS.each { |key| row.delete(key) }
    end

    # How long a process keeps believing the column is absent before asking
    # the database again.
    COLUMN_RECHECK_INTERVAL = 60

    # Only the positive answer is memoised. The negative one expires: on
    # instances where 20260816150000 deferred the ALTER to
    # DataMigrations::AddPointDimensionColumnsJob, the column appears
    # mid-process in Sidekiq while web workers keep serving — a permanent "no"
    # would leave ingest unstamped in every other process until restart.
    # The check queries the catalog rather than Point.column_names because the
    # model's column cache is exactly what goes stale in that window.
    def self.columns_available?
      return true if @columns_available && !Rails.env.test?
      return false if recheck_throttled?

      present = column_in_database?
      # upsert_all validates keys against the model's cached column set, which
      # predates the deferred ALTER in this process.
      Point.reset_column_information if present && !Point.column_names.include?('source_id')
      @columns_available = present
    end

    def self.reset_column_availability!
      @columns_available = nil
      @column_checked_at = nil
    end

    def self.column_in_database?
      ActiveRecord::Base.connection.select_value(<<~SQL.squish).present?
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'points' AND column_name = 'source_id'
      SQL
    end

    def self.recheck_throttled?
      return false if Rails.env.test?

      now = Time.current
      return true if @column_checked_at && now - @column_checked_at < COLUMN_RECHECK_INTERVAL

      @column_checked_at = now
      false
    end
    private_class_method :column_in_database?, :recheck_throttled?

    private

    # Only a resolved id is cached. A nil from a lost race must stay uncached:
    # the resolver is memoised for a whole import, so caching the failure would
    # silently unstamp every later point sharing the combo.
    def source_id_for(row)
      combo = PointSource::COMBO_COLUMNS.map { |column| normalize(column, row) }

      cached = @source_cache[combo]
      return cached if cached

      id = resolve_source(combo)
      @source_cache[combo] = id if id
      id
    end

    # Enum-backed columns arrive as labels ("unplugged") from the API params but
    # are stored as integers. The array columns are nullable and real rows carry
    # both NULL and `{}`: jsonb_build_object renders those as `null` and `[]`,
    # which are different digests, so a nil must stay nil rather than being
    # flattened into an empty array.
    def normalize(column, row)
      key = column.to_sym
      value = row[key]

      case column
      when 'inrids', 'in_regions'
        # Absent and nil are not the same thing. A key the writer never set
        # takes the column default (`{}`) on insert, while a key set to nil is
        # an explicit NULL — and jsonb_build_object renders those as `[]` and
        # `null`, which digest differently.
        return [] unless row.key?(key)

        value.nil? ? nil : Array(value)
      when 'connection', 'trigger', 'battery_status'
        # The enum declarations moved to PointSource when Release D dropped
        # the legacy columns; the mappings are byte-identical to Point's old
        # ones (pinned by spec).
        value.nil? ? nil : PointSource.type_for_attribute(column).serialize(value)
      else value
      end
    end

    def resolve_source(combo)
      scalars = combo[0, 7]
      arrays  = combo[7, 2].map { |value| value&.to_json }

      get_or_create(source_sql, scalars + arrays)
    end

    # One round trip: digest, insert-if-absent, then read back whichever row
    # won. NOT EXISTS matters — Postgres evaluates nextval before it checks the
    # conflict, so relying on ON CONFLICT alone burns an int4 id per repeat, and
    # ingest sees the same handful of combos millions of times a day.
    # ON CONFLICT stays as the guard against a concurrent writer slipping in
    # between the check and the insert; if that race is lost the row is not yet
    # visible to this snapshot, so retry once before giving up.
    def get_or_create(sql, binds)
      2.times do
        id = ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.sanitize_sql_array([sql, *binds])
        )
        return id.to_i if id.present?
      end

      nil
    end

    def source_sql
      @source_sql ||= begin
        columns = PointSource::COMBO_COLUMNS.map { |c| %("#{c}") }.join(', ')
        <<~SQL.squish
          WITH v AS (
            SELECT ?::varchar AS "tracker_id", ?::varchar AS "topic",
                   ?::varchar AS "ssid", ?::varchar AS "bssid",
                   ?::integer AS "connection", ?::integer AS "trigger",
                   ?::integer AS "battery_status",
                   (SELECT CASE WHEN j IS NULL THEN NULL
                                ELSE ARRAY(SELECT jsonb_array_elements_text(j)) END
                    FROM (SELECT ?::jsonb AS j) t)::text[] AS "inrids",
                   (SELECT CASE WHEN j IS NULL THEN NULL
                                ELSE ARRAY(SELECT jsonb_array_elements_text(j)) END
                    FROM (SELECT ?::jsonb AS j) t)::text[] AS "in_regions"
          ), d AS (
            SELECT v.*, #{PointSource.digest_sql('v')} AS digest FROM v
          ), ins AS (
            INSERT INTO point_sources (digest, #{columns}, created_at, updated_at)
            SELECT d.digest, #{columns}, NOW(), NOW() FROM d
            WHERE NOT EXISTS (SELECT 1 FROM point_sources ps WHERE ps.digest = d.digest)
            ON CONFLICT (digest) DO NOTHING
            RETURNING id
          )
          SELECT id FROM ins
          UNION ALL
          SELECT ps.id FROM point_sources ps, d WHERE ps.digest = d.digest
          LIMIT 1
        SQL
      end
    end
  end
end
