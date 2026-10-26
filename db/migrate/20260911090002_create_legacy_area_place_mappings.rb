# frozen_string_literal: true

class CreateLegacyAreaPlaceMappings < ActiveRecord::Migration[8.0]
  def up
    return if table_exists?(:legacy_area_place_mappings)

    create_table :legacy_area_place_mappings do |t|
      t.references :area, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :place, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
  end

  def down
    drop_table :legacy_area_place_mappings, if_exists: true
  end
end
