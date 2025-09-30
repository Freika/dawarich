class ConvertFamilyTablesToBigint < ActiveRecord::Migration[8.0]
  def up
    # Drop dependent tables first
    drop_table :family_invitations if table_exists?(:family_invitations)
    drop_table :family_memberships if table_exists?(:family_memberships)
    drop_table :families if table_exists?(:families)

    # Recreate families table with bigint
    create_table :families do |t|
      t.string :name, null: false, limit: 50
      t.bigint :creator_id, null: false
      t.timestamps
    end

    add_foreign_key :families, :users, column: :creator_id, validate: false
    add_index :families, :creator_id

    # Recreate family_memberships table with bigint
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

    # Recreate family_invitations table with bigint
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

  def down
    # This migration is irreversible since we're changing primary key types
    raise ActiveRecord::IrreversibleMigration
  end
end
