# frozen_string_literal: true

class AddImportIdToExtractionArtifacts < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  TABLES = %i[visits places tracks].freeze

  def up
    TABLES.each do |table|
      add_column table, :import_id, :bigint unless column_exists?(table, :import_id)

      index_name = "idx_#{table}_import_id_extracted"
      next if index_name_exists?(table, index_name)

      add_index table, :import_id,
                where: 'import_id IS NOT NULL',
                algorithm: :concurrently,
                name: index_name
    end
  end

  def down
    TABLES.each do |table|
      index_name = "idx_#{table}_import_id_extracted"
      remove_index table, name: index_name, algorithm: :concurrently if index_name_exists?(table, index_name)

      remove_column table, :import_id if column_exists?(table, :import_id)
    end
  end
end
