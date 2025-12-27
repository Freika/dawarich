# frozen_string_literal: true

class ChangeDigestsDistanceToBigint < ActiveRecord::Migration[8.0]
  # Safe: digests table is new with minimal data
  disable_ddl_transaction!

  def change
    if respond_to?(:safety_assured)
      safety_assured do
        change_column :digests, :distance, :bigint, null: false, default: 0
      end
    else
      change_column :digests, :distance, :bigint, null: false, default: 0
    end
  end
end
