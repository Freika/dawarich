# frozen_string_literal: true

class AddExtractionColumnsToImports < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_imports_on_additional_data_extraction_status'

  def up
    unless column_exists?(:imports, :additional_data_extraction_status)
      add_column :imports, :additional_data_extraction_status, :integer, default: 0, null: false
    end

    unless column_exists?(:imports, :additional_data_extraction)
      add_column :imports, :additional_data_extraction, :jsonb, default: {}, null: false
    end

    return if index_name_exists?(:imports, INDEX_NAME)

    add_index :imports, :additional_data_extraction_status,
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    remove_index :imports, name: INDEX_NAME, algorithm: :concurrently if index_name_exists?(:imports, INDEX_NAME)
    remove_column :imports, :additional_data_extraction if column_exists?(:imports, :additional_data_extraction)

    return unless column_exists?(:imports, :additional_data_extraction_status)

    remove_column :imports, :additional_data_extraction_status
  end
end
