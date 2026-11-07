# frozen_string_literal: true

class LoadTimezoneBoundaries < ActiveRecord::Migration[8.1]
  # The loader commits on its own; outside a DDL transaction a failed load
  # cannot leave the connection aborted for the migrations that follow.
  disable_ddl_transaction!

  def up
    Timezones::LoadBoundaries.call_safely('Migration')
  end

  def down; end
end
