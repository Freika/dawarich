# frozen_string_literal: true

class AddAnomalyOverrideToPoints < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LOCK_TIMEOUT = '5s'
  MAX_ATTEMPTS = 5

  def up
    attempts = 0
    begin
      attempts += 1
      transaction do
        connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
        add_column :points, :anomaly_override, :boolean, default: false, null: false, if_not_exists: true
      end
    rescue ActiveRecord::LockWaitTimeout
      raise if attempts >= MAX_ATTEMPTS

      sleep(attempts * 5)
      retry
    end
  end

  def down
    remove_column :points, :anomaly_override, if_exists: true
  end
end
