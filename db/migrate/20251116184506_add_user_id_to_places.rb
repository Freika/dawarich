class AddUserIdToPlaces < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Add nullable for backward compatibility, will enforce later via data migration
    add_reference :places, :user, null: true, index: {algorithm: :concurrently} unless foreign_key_exists?(:places, :users)
  end

  def down
    remove_reference :places, :user, index: true if foreign_key_exists?(:places, :users)
  end
end
