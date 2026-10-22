# frozen_string_literal: true

class AddPointRevisions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LOCK_TIMEOUT = '5s'
  MAX_ATTEMPTS = 5
  INDEX_NAME = 'index_point_revisions_on_user_id_and_month'
  MONTH = "date_trunc('month', to_timestamp(timestamp) AT TIME ZONE 'UTC')::date"
  EVENTS = {
    insert: ['SELECT user_id, timestamp FROM new_points', 'AFTER', 'NEW TABLE AS new_points'],
    update: ['SELECT user_id, timestamp FROM old_points UNION ALL SELECT user_id, timestamp FROM new_points',
             'AFTER', 'OLD TABLE AS old_points NEW TABLE AS new_points'],
    delete: ['SELECT user_id, timestamp FROM old_points', 'AFTER', 'OLD TABLE AS old_points'],
    truncate: ['SELECT user_id, timestamp FROM points', 'BEFORE', nil]
  }.freeze

  def up
    create_revisions_table
    unless index_name_exists?(:point_revisions, INDEX_NAME)
      add_index :point_revisions, %i[user_id month], unique: true, name: INDEX_NAME
    end
    EVENTS.each { |event, (source, timing, references)| create_trigger(event, source, timing, references) }
  end

  def down
    EVENTS.each_key do |event|
      with_points_lock { execute "DROP TRIGGER IF EXISTS points_revision_#{event} ON points" }
      execute "DROP FUNCTION IF EXISTS points_revision_#{event}()"
    end
    drop_table :point_revisions, if_exists: true
  end

  private

  def create_revisions_table
    return if table_exists?(:point_revisions)

    create_table :point_revisions do |table| # rubocop:disable Rails/CreateTableWithTimestamps
      table.bigint :user_id, null: false
      table.date :month, null: false
      table.uuid :revision, null: false, default: -> { 'gen_random_uuid()' }
    end
  end

  def create_trigger(event, source, timing, references)
    execute <<~SQL
      CREATE OR REPLACE FUNCTION points_revision_#{event}() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        INSERT INTO point_revisions (user_id, month, revision)
        SELECT user_id, #{MONTH}, gen_random_uuid()
        FROM (#{source}) AS changed
        WHERE user_id IS NOT NULL AND timestamp IS NOT NULL
        GROUP BY user_id, #{MONTH}
        ORDER BY user_id, #{MONTH}
        ON CONFLICT (user_id, month) DO UPDATE SET revision = EXCLUDED.revision;
        RETURN NULL;
      END;
      $$;
    SQL
    with_points_lock do
      execute "DROP TRIGGER IF EXISTS points_revision_#{event} ON points"
      execute <<~SQL
        CREATE TRIGGER points_revision_#{event} #{timing} #{event.to_s.upcase} ON points
        #{"REFERENCING #{references}" if references} FOR EACH STATEMENT EXECUTE FUNCTION points_revision_#{event}();
      SQL
    end
  end

  def with_points_lock
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
