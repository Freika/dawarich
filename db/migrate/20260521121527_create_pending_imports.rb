# frozen_string_literal: true

class CreatePendingImports < ActiveRecord::Migration[8.0]
  def change
    enable_extension 'pgcrypto'

    create_table :pending_imports do |t|
      t.uuid :claim_ticket, null: false, default: -> { 'gen_random_uuid()' }
      t.string :original_filename, null: false
      t.string :source_hint
      t.string :origin, null: false
      t.datetime :expires_at, null: false
      t.datetime :claimed_at
      t.bigint :claimed_by_user_id
      t.timestamps
    end

    add_index :pending_imports, :claim_ticket, unique: true
    add_index :pending_imports, :expires_at
    add_index :pending_imports, :claimed_by_user_id
    add_foreign_key :pending_imports, :users, column: :claimed_by_user_id, on_delete: :nullify
  end
end
