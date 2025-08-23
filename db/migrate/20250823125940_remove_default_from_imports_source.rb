class RemoveDefaultFromImportsSource < ActiveRecord::Migration[8.0]
  def change
    change_column_default :imports, :source, from: 0, to: nil
  end
end
