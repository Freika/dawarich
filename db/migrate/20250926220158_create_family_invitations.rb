# frozen_string_literal: true

class CreateFamilyInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :family_invitations do |t|
      t.bigint :family_id, null: false
      t.string :email, null: false
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.bigint :invited_by_id, null: false
      t.integer :status, null: false, default: 0 # pending
      t.timestamps
    end

    add_foreign_key :family_invitations, :families, validate: false
    add_foreign_key :family_invitations, :users, column: :invited_by_id, validate: false
    add_index :family_invitations, :family_id
    add_index :family_invitations, :email
    add_index :family_invitations, :token, unique: true
    add_index :family_invitations, :status
    add_index :family_invitations, :expires_at
  end
end
