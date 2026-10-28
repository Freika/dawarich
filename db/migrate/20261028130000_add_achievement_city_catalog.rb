# frozen_string_literal: true

class AddAchievementCityCatalog < ActiveRecord::Migration[8.1]
  def change
    add_column :exploration_territories, :kind, :string, null: false, default: 'country'
    add_column :exploration_territories, :timezone, :string
    add_column :exploration_territories, :source_metadata, :jsonb, null: false, default: {}
    add_index :exploration_territories, %i[dataset_id kind]

    create_table :achievement_city_selections do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :territory_code, null: false
      t.boolean :share_mosaic, null: false, default: false
      t.timestamps
    end
    add_index :achievement_city_selections, %i[user_id territory_code], unique: true
    add_reference :achievement_collectibles, :city_selection,
                  foreign_key: { to_table: :achievement_city_selections, on_delete: :nullify }
  end
end
