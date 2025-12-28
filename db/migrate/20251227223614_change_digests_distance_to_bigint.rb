# frozen_string_literal: true

class ChangeDigestsDistanceToBigint < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    safety_assured { change_column :digests, :distance, :bigint, null: false, default: 0 }
  end

  def down
    safety_assured { change_column :digests, :distance, :integer, null: false, default: 0 }
  end
end
