# frozen_string_literal: true

# Helpers for specs that race two connections on the monthly revision rows.
module RevisionLockHelpers
  PER_USER_TRIGGER_TABLES = %w[points tracks track_segments].freeze

  # Achievement and exploration triggers upsert one row per user on every
  # write, which queues same-user writers before they reach the monthly
  # revision rows and hides their lock order. Switch them off so a spec sees
  # the order on its own.
  def without_per_user_triggers
    toggle_per_user_triggers('DISABLE')
    yield
  ensure
    toggle_per_user_triggers('ENABLE')
  end

  def in_thread(&)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&) }
  end

  def backend_pid(connection = ActiveRecord::Base.connection)
    connection.select_value('SELECT pg_backend_pid()')
  end

  # pg_stat_activity is snapshotted per transaction, so clear it on every poll.
  def wait_for_lock_wait(pid)
    Timeout.timeout(5) do
      sleep 0.05 until ActiveRecord::Base.connection.select_value(<<~SQL.squish).positive?
        SELECT count(*) FROM (SELECT pg_stat_clear_snapshot()) AS cleared, pg_stat_activity
        WHERE pid = #{Integer(pid)} AND wait_event_type = 'Lock'
      SQL
    end
  end

  def delete_user_data(user)
    connection = ActiveRecord::Base.connection
    %w[point_revisions track_revisions].each { |t| connection.execute("DELETE FROM #{t} WHERE user_id = #{user.id}") }
    SharedLink.where(user_id: user.id).delete_all
    Point.where(user_id: user.id).delete_all
    TrackSegment.where(track_id: Track.where(user_id: user.id).select(:id)).delete_all
    Track.where(user_id: user.id).delete_all
    user.delete
  end

  private

  def toggle_per_user_triggers(action)
    connection = ActiveRecord::Base.connection
    PER_USER_TRIGGER_TABLES.each do |table|
      connection.select_values(<<~SQL.squish).each do |trigger|
        SELECT tgname FROM pg_trigger WHERE tgrelid = '#{table}'::regclass
        AND (tgname LIKE 'achievement_collections\\_%' OR tgname LIKE 'exploration\\_%')
      SQL
        connection.execute("ALTER TABLE #{table} #{action} TRIGGER #{connection.quote_column_name(trigger)}")
      end
    end
  end
end
