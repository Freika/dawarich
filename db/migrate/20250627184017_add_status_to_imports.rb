# frozen_string_literal: true

class AddStatusToImports < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :imports, :status, :integer, default: 0, null: false
    add_index :imports, :status, algorithm: :concurrently

    # Raw SQL: loading the Import AR model here pulls in User (via belongs_to
    # and `legacy_trial?` validation), whose HEAD enums (subscription_source,
    # plan, etc.) reference columns added by later migrations. Long-jump
    # upgrades would crash with "Undeclared attribute type for enum". See #2362.
    # status enum: 0 = created, 1 = processing, 2 = completed
    execute 'UPDATE imports SET status = 2'
  end
end
