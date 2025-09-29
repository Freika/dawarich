# frozen_string_literal: true

class AddSharingFieldsToStats < ActiveRecord::Migration[8.0]
  def up
    add_column :stats, :sharing_settings, :jsonb
    add_column :stats, :sharing_uuid, :uuid

    change_column_default :stats, :sharing_settings, {}

    BulkStatsCalculatingJob.set(wait: 5.minutes).perform_later
  end

  def down
    remove_column :stats, :sharing_settings
    remove_column :stats, :sharing_uuid
  end
end
