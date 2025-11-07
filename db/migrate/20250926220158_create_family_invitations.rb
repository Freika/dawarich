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

    add_foreign_key :family_invitations, :families
    add_foreign_key :family_invitations, :users, column: :invited_by_id
    add_index :family_invitations, :token, unique: true
    add_index :family_invitations, %i[family_id email], name: 'index_family_invitations_on_family_id_and_email'
    add_index :family_invitations, %i[family_id status expires_at],
              name: 'index_family_invitations_on_family_status_expires'
    add_index :family_invitations, %i[status expires_at],
              name: 'index_family_invitations_on_status_and_expires_at'
    add_index :family_invitations, %i[status updated_at],
              name: 'index_family_invitations_on_status_and_updated_at'
  end
end
