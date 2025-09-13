# frozen_string_literal: true

class AddSharingFieldsToStats < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :stats, :sharing_settings, :jsonb
    add_column :stats, :sharing_uuid, :uuid

    change_column_default :stats, :sharing_settings, {}
  end

  def down
    remove_column :stats, :sharing_settings
    remove_column :stats, :sharing_uuid
  end
end
