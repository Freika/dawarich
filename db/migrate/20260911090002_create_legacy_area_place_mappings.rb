# frozen_string_literal: true

class CreateLegacyAreaPlaceMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :legacy_area_place_mappings do |t|
      t.references :area, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :place, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
  end
end
