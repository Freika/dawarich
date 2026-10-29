# frozen_string_literal: true

class LoadTimezoneBoundaries < ActiveRecord::Migration[8.1]
  # The loader commits on its own; outside a DDL transaction a failed load
  # cannot leave the connection aborted for the migrations that follow.
  disable_ddl_transaction!

  def up
    Timezones::LoadBoundaries.new.call
  rescue StandardError => e
    # An empty table only means timeline times stay in the account time zone,
    # so a failed load must not stop the upgrade.
    message = "Time zone boundaries were not loaded (#{e.class}: #{e.message}); " \
              'db:seed retries on the next start, or run Timezones::LoadBoundaries.new.call'
    Rails.logger.warn("[Migration] #{message}")
  end

  def down; end
end
