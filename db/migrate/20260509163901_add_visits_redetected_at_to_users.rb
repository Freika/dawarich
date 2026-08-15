# frozen_string_literal: true

class AddVisitsRedetectedAtToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :users, :visits_redetected_at, :datetime, if_not_exists: true
    add_index :users, :visits_redetected_at, algorithm: :concurrently, if_not_exists: true
  end
end
