# frozen_string_literal: true

class AddStartedAtIndexToVisits < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :visits, :started_at, algorithm: :concurrently
  end
end
