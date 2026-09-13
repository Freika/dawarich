# frozen_string_literal: true

class CreateServiceSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :service_settings, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :service, null: false
      t.string :provider, null: false
      t.jsonb :config, null: false, default: {}
      t.text :credentials
      t.boolean :active, null: false, default: false

      t.timestamps
    end

    add_index :service_settings, %i[user_id service provider], unique: true, if_not_exists: true
    add_index :service_settings, %i[user_id service],
              unique: true,
              where: 'active',
              name: 'index_service_settings_on_user_service_active',
              if_not_exists: true
  end
end
