# frozen_string_literal: true

class AddTrackRevisions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LOCK_TIMEOUT = '5s'
  MAX_ATTEMPTS = 5
  INDEX_NAME = 'index_track_revisions_on_user_id_and_month'
  EVENTS = {
    insert: ['SELECT user_id, start_at, end_at FROM new_tracks', 'AFTER', 'NEW TABLE AS new_tracks'],
    update: ['SELECT user_id, start_at, end_at FROM old_tracks UNION ALL ' \
             'SELECT user_id, start_at, end_at FROM new_tracks',
             'AFTER', 'OLD TABLE AS old_tracks NEW TABLE AS new_tracks'],
    delete: ['SELECT user_id, start_at, end_at FROM old_tracks', 'AFTER', 'OLD TABLE AS old_tracks'],
    truncate: ['SELECT user_id, start_at, end_at FROM tracks', 'BEFORE', nil]
  }.freeze

  def up
    create_revisions_table
    unless index_name_exists?(:track_revisions, INDEX_NAME)
      add_index :track_revisions, %i[user_id month], unique: true, name: INDEX_NAME
    end
    EVENTS.each { |event, (source, timing, references)| create_trigger(event, source, timing, references) }
  end

  def down
    EVENTS.each_key do |event|
      with_tracks_lock { execute "DROP TRIGGER IF EXISTS tracks_revision_#{event} ON tracks" }
      execute "DROP FUNCTION IF EXISTS tracks_revision_#{event}()"
    end
    drop_table :track_revisions, if_exists: true
  end

  private

  def create_revisions_table
    return if table_exists?(:track_revisions)

    create_table :track_revisions do |table| # rubocop:disable Rails/CreateTableWithTimestamps
      table.bigint :user_id, null: false
      table.date :month, null: false
      table.uuid :revision, null: false, default: -> { 'gen_random_uuid()' }
    end
  end

  def create_trigger(event, source, timing, references)
    execute <<~SQL
      CREATE OR REPLACE FUNCTION tracks_revision_#{event}() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        INSERT INTO track_revisions (user_id, month, revision)
        SELECT changed.user_id, months.month::date, gen_random_uuid()
        FROM (#{source}) AS changed
        CROSS JOIN LATERAL generate_series(
          date_trunc('month', changed.start_at), date_trunc('month', changed.end_at), interval '1 month'
        ) AS months(month)
        WHERE changed.user_id IS NOT NULL AND changed.start_at IS NOT NULL AND changed.end_at IS NOT NULL
        GROUP BY changed.user_id, months.month
        ORDER BY changed.user_id, months.month
        ON CONFLICT (user_id, month) DO UPDATE SET revision = EXCLUDED.revision;
        RETURN NULL;
      END;
      $$;
    SQL
    with_tracks_lock do
      execute "DROP TRIGGER IF EXISTS tracks_revision_#{event} ON tracks"
      execute <<~SQL
        CREATE TRIGGER tracks_revision_#{event} #{timing} #{event.to_s.upcase} ON tracks
        #{"REFERENCING #{references}" if references} FOR EACH STATEMENT EXECUTE FUNCTION tracks_revision_#{event}();
      SQL
    end
  end

  def with_tracks_lock
    attempts = 0
    begin
      attempts += 1
      transaction do
        connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
        yield
      end
    rescue ActiveRecord::LockWaitTimeout
      raise if attempts >= MAX_ATTEMPTS

      sleep(attempts * 5)
      retry
    end
  end
end
