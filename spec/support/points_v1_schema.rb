# frozen_string_literal: true

# Rebuilds the v1 (pre-Release-D) shape of the points table for specs that
# exercise the rewrite itself or the new-code-on-old-schema boot window.
# The DDL mirrors db/schema.rb as of dev @ 1c0cbcfa (the last v1 schema).
module PointsV1Schema
  V1_DDL = <<~SQL
    CREATE TABLE points (
      id bigint PRIMARY KEY DEFAULT nextval('points_id_seq'),
      accuracy integer,
      altitude integer,
      altitude_decimal numeric(10,2),
      anomaly boolean,
      battery integer,
      battery_status integer,
      bssid character varying,
      city character varying,
      connection integer,
      country character varying,
      country_id bigint,
      country_name character varying,
      course numeric(8,5),
      course_accuracy numeric(8,5),
      created_at timestamp(6) without time zone NOT NULL,
      external_track_id character varying,
      geodata jsonb NOT NULL DEFAULT '{}'::jsonb,
      import_id bigint,
      in_regions text[] DEFAULT '{}',
      inrids text[] DEFAULT '{}',
      lonlat geography(Point,4326),
      mode integer,
      motion_data jsonb NOT NULL DEFAULT '{}'::jsonb,
      ping character varying,
      raw_data jsonb DEFAULT '{}'::jsonb,
      raw_data_archive_id bigint,
      raw_data_archived boolean NOT NULL DEFAULT false,
      reverse_geocoded_at timestamp(6) without time zone,
      source_id integer,
      ssid character varying,
      "timestamp" integer,
      topic character varying,
      track_id bigint,
      tracker_id character varying,
      trigger integer,
      updated_at timestamp(6) without time zone NOT NULL,
      user_id bigint,
      velocity character varying,
      vertical_accuracy integer,
      visit_id bigint
    );
    CREATE UNIQUE INDEX index_points_on_user_id_timestamp_lonlat
      ON points (user_id, "timestamp", lonlat);
    CREATE INDEX index_points_on_lonlat ON points USING gist (lonlat);
    CREATE INDEX idx_points_track_id_timestamp ON points (track_id, "timestamp");
    CREATE INDEX index_points_on_import_id ON points (import_id);
    CREATE INDEX index_points_on_visit_id ON points (visit_id);
    CREATE INDEX index_points_on_raw_data_archive_id ON points (raw_data_archive_id);
    CREATE INDEX index_points_on_not_reverse_geocoded ON points (id)
      WHERE reverse_geocoded_at IS NULL;
    CREATE INDEX index_points_on_unarchived ON points (user_id, id)
      WHERE raw_data_archived = false AND raw_data <> '{}'::jsonb;
    CREATE INDEX idx_points_user_id_legacy_tracker ON points (user_id)
      WHERE tracker_id::text = ANY (ARRAY['google-maps-timeline-export'::text,
                                          'google-maps-phone-timeline-export'::text]);
  SQL

  module_function

  def connection = ActiveRecord::Base.connection

  # Swaps whatever `points` currently is aside and installs a v1-shaped one.
  # Always pair with restore_real_points in an ensure block.
  def install_v1_points
    connection.execute(<<~SQL)
      ALTER SEQUENCE IF EXISTS points_id_seq OWNED BY NONE;
      DROP TABLE IF EXISTS points_spec_backup CASCADE;
      ALTER TABLE points RENAME TO points_spec_backup;
      CREATE SEQUENCE IF NOT EXISTS points_id_seq;
    SQL
    rename_indexes('points_spec_backup', suffix: '_specbak')
    connection.execute(V1_DDL)
    clear_caches
  end

  def restore_real_points
    connection.execute(<<~SQL)
      ALTER SEQUENCE IF EXISTS points_id_seq OWNED BY NONE;
      DROP TABLE IF EXISTS points CASCADE;
      DROP TABLE IF EXISTS points_legacy_d CASCADE;
      DROP TABLE IF EXISTS points_v2 CASCADE;
      ALTER TABLE points_spec_backup RENAME TO points;
      CREATE SEQUENCE IF NOT EXISTS points_id_seq;
      ALTER TABLE points ALTER COLUMN id SET DEFAULT nextval('points_id_seq');
      ALTER SEQUENCE points_id_seq OWNED BY points.id;
    SQL
    connection.execute(
      "SELECT setval('points_id_seq', COALESCE((SELECT MAX(id) FROM points), 1))"
    )
    rename_indexes('points', strip: '_specbak')
    clear_caches
  end

  def rename_indexes(table, suffix: nil, strip: nil)
    connection.select_values(
      "SELECT indexname FROM pg_indexes WHERE tablename = #{connection.quote(table)}"
    ).each do |index|
      new_name = suffix ? "#{index}#{suffix}"[0, 63] : index.sub(strip, '')
      next if new_name == index

      connection.execute(%(ALTER INDEX "#{index}" RENAME TO "#{new_name}"))
    end
  end

  def clear_caches
    connection.schema_cache.clear!
    # Transitional: while the branch still carries v1 enum declarations,
    # resetting Point against a v2 table raises; tolerate until Task 5
    # removes the enums, after which this rescues nothing.
    begin
      Point.reset_column_information
    rescue RuntimeError => e
      raise unless e.message.include?('enum')
    end
  end
end
