class AddUserIdToPlaces < ActiveRecord::Migration[8.0]
  def change
    # Add nullable for backward compatibility, will enforce later via data migration
    add_reference :places, :user, null: true, foreign_key: true, index: true
  end
end
