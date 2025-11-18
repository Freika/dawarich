class AddNoteToPlaces < ActiveRecord::Migration[8.0]
  def change
    add_column :places, :note, :text
  end
end
