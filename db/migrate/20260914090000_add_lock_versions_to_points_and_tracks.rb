# frozen_string_literal: true

class AddLockVersionsToPointsAndTracks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  LOCK_TIMEOUT = '5s'
  MAX_ATTEMPTS = 5

  def up
    %i[points tracks].each { |table| add_lock_version(table) }
  end

  def down
    remove_column :tracks, :lock_version, if_exists: true
    remove_column :points, :lock_version, if_exists: true
  end

  private

  def add_lock_version(table)
    attempts = 0
    begin
      attempts += 1
      transaction do
        connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
        add_column table, :lock_version, :integer, null: false, default: 0, if_not_exists: true
      end
    rescue ActiveRecord::LockWaitTimeout
      raise if attempts >= MAX_ATTEMPTS

      sleep(attempts * 5)
      retry
    end
  end
end
