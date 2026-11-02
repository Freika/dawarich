# frozen_string_literal: true

class AddAchievementCityCatalog < ActiveRecord::Migration[8.1]
  def up
    add_column :exploration_territories, :kind, :string, null: false, default: 'country', if_not_exists: true
    add_column :exploration_territories, :timezone, :string, if_not_exists: true
    add_column :exploration_territories, :source_metadata, :jsonb, null: false, default: {}, if_not_exists: true
    add_index :exploration_territories, %i[dataset_id kind], if_not_exists: true

    create_table :achievement_city_selections, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :territory_code, null: false
      t.boolean :share_mosaic, null: false, default: false
      t.timestamps
    end
    add_index :achievement_city_selections, %i[user_id territory_code], unique: true, if_not_exists: true
    add_column :achievement_collectibles, :city_selection_id, :bigint, if_not_exists: true
    add_index :achievement_collectibles, :city_selection_id, if_not_exists: true
    add_foreign_key :achievement_collectibles, :achievement_city_selections,
                    column: :city_selection_id, on_delete: :nullify, if_not_exists: true
    add_index :achievement_city_selections, :user_id, if_not_exists: true
    add_foreign_key :achievement_city_selections, :users, column: :user_id, on_delete: :cascade, if_not_exists: true
  end

  def down
    if table_exists?(:achievement_collectibles)
      remove_column :achievement_collectibles, :city_selection_id,
                    if_exists: true
    end
    drop_table :achievement_city_selections, if_exists: true
    if table_exists?(:exploration_territories)
      remove_index :exploration_territories, %i[dataset_id kind],
                   if_exists: true
    end
    remove_column :exploration_territories, :source_metadata, if_exists: true if table_exists?(:exploration_territories)
    remove_column :exploration_territories, :timezone, if_exists: true if table_exists?(:exploration_territories)
    remove_column :exploration_territories, :kind, if_exists: true if table_exists?(:exploration_territories)
  end
end
