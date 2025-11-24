class AddOmniauthToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :users, :provider, :string unless column_exists?(:users, :provider)
    add_column :users, :uid, :string unless column_exists?(:users, :uid)
    add_index :users, [:provider, :uid], unique: true, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :users, column: [:provider, :uid], algorithm: :concurrently, if_exists: true
    remove_column :users, :uid if column_exists?(:users, :uid)
    remove_column :users, :provider if column_exists?(:users, :provider)
  end
end
