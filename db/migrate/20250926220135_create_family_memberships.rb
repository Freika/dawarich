# frozen_string_literal: true

class CreateFamilyMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :family_memberships do |t|
      t.bigint :family_id, null: false
      t.bigint :user_id, null: false
      t.integer :role, null: false, default: 1 # member
      t.timestamps
    end

    add_foreign_key :family_memberships, :families, validate: false
    add_foreign_key :family_memberships, :users, validate: false
    add_index :family_memberships, :family_id
    add_index :family_memberships, :user_id, unique: true # One family per user
    add_index :family_memberships, %i[family_id role]
  end
end
