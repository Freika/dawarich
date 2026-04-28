# frozen_string_literal: true

class CreateFlipperTables < ActiveRecord::Migration[8.0]
  def up
    unless table_exists?(:flipper_features)
      create_table :flipper_features do |t|
        t.string :key, null: false
        t.timestamps null: false
      end
    end

    unless index_name_exists?(:flipper_features, :index_flipper_features_on_key)
      add_index :flipper_features, :key, unique: true
    end

    unless table_exists?(:flipper_gates)
      create_table :flipper_gates do |t|
        t.string :feature_key, null: false
        t.string :key, null: false
        t.text :value
        t.timestamps null: false
      end
    end

    return if index_name_exists?(:flipper_gates, :index_flipper_gates_on_feature_key_and_key_and_value)

    add_index :flipper_gates, %i[feature_key key value], unique: true, length: { value: 255 }
  end

  def down
    drop_table :flipper_gates if table_exists?(:flipper_gates)
    drop_table :flipper_features if table_exists?(:flipper_features)
  end
end
