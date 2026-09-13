# frozen_string_literal: true

class AddPointsTrackForeignKey < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LOCK_TIMEOUT = '5s'
  MAX_ATTEMPTS = 5

  def up
    return if foreign_key_exists?(:points, :tracks, column: :track_id)

    attempts = 0
    begin
      attempts += 1
      transaction do
        connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
        add_foreign_key :points, :tracks, column: :track_id, validate: false
      end
    rescue ActiveRecord::LockWaitTimeout
      raise if attempts >= MAX_ATTEMPTS

      sleep(attempts * 5)
      retry
    end
  end

  def down
    remove_foreign_key :points, :tracks, column: :track_id, if_exists: true
  end
end
