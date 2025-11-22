class AddNoteToPlaces < ActiveRecord::Migration[8.0]
  def change
    add_column :places, :note, :text unless column_exists? :places, :note
  end
end
