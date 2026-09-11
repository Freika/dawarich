# frozen_string_literal: true

class CreatePushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :installation_id, null: false
      t.string :push_token, null: false
      t.string :provider, null: false
      t.string :environment
      t.string :api_key_digest, null: false
      t.string :context_id, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :push_subscriptions, %i[provider environment push_token], unique: true,
              nulls_not_distinct: true, name: :index_push_subscriptions_on_delivery_token
    add_index :push_subscriptions, %i[user_id installation_id], unique: true
  end
end
