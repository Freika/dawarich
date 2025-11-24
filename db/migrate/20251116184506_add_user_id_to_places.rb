class AddUserIdToPlaces < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Add nullable for backward compatibility, will enforce later via data migration
    unless column_exists?(:places, :user_id)
      add_reference :places, :user, null: true, index: { algorithm: :concurrently }
    end
  end

  def down
    remove_reference :places, :user, index: true if column_exists?(:places, :user_id)
  end
end
