class AddDeletedAtToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :users, :deleted_at, :datetime unless column_exists?(:users, :deleted_at)
    add_index :users, :deleted_at, algorithm: :concurrently unless index_exists?(:users, :deleted_at)
  end
end
