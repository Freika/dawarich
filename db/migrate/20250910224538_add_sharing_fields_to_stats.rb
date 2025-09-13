# frozen_string_literal: true

class AddSharingFieldsToStats < ActiveRecord::Migration[8.0]
  def change
    add_column :stats, :sharing_settings, :jsonb, default: {}
    add_column :stats, :sharing_uuid, :uuid
  end
end
