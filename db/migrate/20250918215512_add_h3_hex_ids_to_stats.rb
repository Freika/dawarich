# frozen_string_literal: true

class AddH3HexIdsToStats < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :stats, :h3_hex_ids, :jsonb, default: {}, if_not_exists: true
    add_index :stats, :h3_hex_ids, using: :gin,
              where: "(h3_hex_ids IS NOT NULL AND h3_hex_ids != '{}'::jsonb)",
              algorithm: :concurrently, if_not_exists: true
  end
end
