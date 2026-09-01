# frozen_string_literal: true

# Release D, stage 1: the empty v2 points table in its frozen shape
# (superpowers plan 2026-08-31-points-v2-column-freeze.md). Columns are
# ordered by descending alignment; the id continues points_id_seq so rows
# written to either table during the rewrite window can never collide.
# Indexes and foreign keys are added by DataMigrations::RewritePointsV2Job
# after the copy — only the primary key exists from the start, because the
# copy and the change-capture catch-up upsert ON CONFLICT (id).
class CreatePointsV2 < ActiveRecord::Migration[8.0]
  def up
    return unless v1_points?
    return if table_exists?(:points_v2)

    execute <<~SQL
      CREATE TABLE points_v2 (
        id                  bigint PRIMARY KEY DEFAULT nextval('points_id_seq'),
        "timestamp"         bigint NOT NULL,
        user_id             bigint NOT NULL,
        track_id            bigint,
        import_id           bigint,
        visit_id            bigint,
        raw_data_archive_id bigint,
        created_at          timestamp(6) without time zone NOT NULL,
        updated_at          timestamp(6) without time zone NOT NULL,
        reverse_geocoded_at timestamp(6) without time zone,
        country_id          integer,
        source_id           integer,
        accuracy            integer,
        vertical_accuracy   integer,
        altitude            real,
        velocity            real,
        course              real,
        course_accuracy     real,
        battery             smallint,
        anomaly             boolean,
        raw_data_archived   boolean NOT NULL DEFAULT false,
        lonlat              geography(Point,4326),
        city                character varying,
        geodata             jsonb NOT NULL DEFAULT '{}'::jsonb,
        raw_data            jsonb DEFAULT '{}'::jsonb,
        motion_data         jsonb NOT NULL DEFAULT '{}'::jsonb
      )
    SQL
  end

  def down
    drop_table :points_v2, if_exists: true
  end

  private

  # v1 is recognised by a column the rewrite drops; once the swap has run,
  # points no longer has it and every stage of the rewrite becomes a no-op.
  def v1_points?
    column_exists?(:points, :country_name)
  end
end
