# frozen_string_literal: true

class AddUniqueIndexToRawDataArchives < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :points_raw_data_archives,
              %i[user_id year month chunk_number],
              unique: true,
              name: 'index_raw_data_archives_uniqueness',
              algorithm: :concurrently
  end
end
