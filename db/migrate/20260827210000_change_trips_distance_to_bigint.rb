# frozen_string_literal: true

class ChangeTripsDistanceToBigint < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LOCK_TIMEOUT = '5s'
  MAX_ATTEMPTS = 5

  def up
    return if already_bigint?

    attempts = 0
    begin
      attempts += 1
      transaction do
        connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
        change_column :trips, :distance, :bigint
      end
    rescue ActiveRecord::LockWaitTimeout
      raise if attempts >= MAX_ATTEMPTS

      sleep(attempts * 5)
      retry
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Cannot safely narrow trips.distance back to integer after bigint values have been persisted.'
  end

  private

  # Postgres bigint columns report .type as :integer (limit 8); only sql_type
  # distinguishes them from a 4-byte integer.
  def already_bigint?
    connection.columns(:trips).find { |c| c.name == 'distance' }&.sql_type == 'bigint'
  end
end
