# frozen_string_literal: true

class AddPointRevisions < ActiveRecord::Migration[8.1]
  def up
    create_table :point_revisions do |table| # rubocop:disable Rails/CreateTableWithTimestamps
      table.bigint :user_id, null: false
      table.date :month, null: false
      table.uuid :revision, null: false, default: -> { 'gen_random_uuid()' }
    end
    add_index :point_revisions, %i[user_id month], unique: true

    { insert: 'SELECT user_id, timestamp FROM new_points',
      update: 'SELECT user_id, timestamp FROM old_points UNION ALL SELECT user_id, timestamp FROM new_points',
      delete: 'SELECT user_id, timestamp FROM old_points',
      truncate: 'SELECT user_id, timestamp FROM points' }.each do |event, source|
      execute <<~SQL
        CREATE FUNCTION points_revision_#{event}() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          INSERT INTO point_revisions (user_id, month, revision)
          SELECT user_id, date_trunc('month', to_timestamp(timestamp) AT TIME ZONE 'UTC')::date, gen_random_uuid()
          FROM (#{source}) AS changed
          WHERE user_id IS NOT NULL AND timestamp IS NOT NULL
          GROUP BY user_id, date_trunc('month', to_timestamp(timestamp) AT TIME ZONE 'UTC')::date
          ORDER BY user_id, date_trunc('month', to_timestamp(timestamp) AT TIME ZONE 'UTC')::date
          ON CONFLICT (user_id, month) DO UPDATE SET revision = EXCLUDED.revision;
          RETURN NULL;
        END;
        $$;
      SQL
      references = case event
                   when :insert then 'NEW TABLE AS new_points'
                   when :delete then 'OLD TABLE AS old_points'
                   when :truncate then nil
                   else 'OLD TABLE AS old_points NEW TABLE AS new_points'
                   end
      execute <<~SQL
        CREATE TRIGGER points_revision_#{event} #{event == :truncate ? 'BEFORE' : 'AFTER'} #{event.to_s.upcase} ON points
        #{"REFERENCING #{references}" if references} FOR EACH STATEMENT EXECUTE FUNCTION points_revision_#{event}();
      SQL
    end
  end

  def down
    %w[insert update delete truncate].each do |event|
      execute "DROP TRIGGER IF EXISTS points_revision_#{event} ON points"
      execute "DROP FUNCTION IF EXISTS points_revision_#{event}()"
    end
    drop_table :point_revisions
  end
end
