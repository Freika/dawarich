# frozen_string_literal: true

class CreateFamilyLocationRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :family_location_requests do |t|
      t.bigint :requester_id, null: false
      t.bigint :target_user_id, null: false
      t.bigint :family_id, null: false
      t.integer :status, null: false, default: 0
      t.string :suggested_duration, null: false, default: '24h'
      t.datetime :expires_at, null: false
      t.datetime :responded_at

      t.timestamps
    end

    add_index :family_location_requests, %i[requester_id target_user_id status],
              name: :idx_family_loc_requests_requester_target_status
    add_index :family_location_requests, %i[target_user_id status],
              name: :idx_family_loc_requests_target_status
    add_index :family_location_requests, %i[expires_at status],
              name: :idx_family_loc_requests_expires_status
    add_index :family_location_requests, :family_id

    add_foreign_key :family_location_requests, :users, column: :requester_id
    add_foreign_key :family_location_requests, :users, column: :target_user_id
    add_foreign_key :family_location_requests, :families
  end
end
