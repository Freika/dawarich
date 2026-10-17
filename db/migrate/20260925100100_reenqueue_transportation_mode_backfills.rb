# frozen_string_literal: true

class ReenqueueTransportationModeBackfills < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  SUPPORTED_SOURCE_IDS = [0, 1, 2, 3, 6].freeze

  def up
    if connection.select_value('SELECT EXISTS (SELECT 1 FROM tracks)')
      DataMigrations::BackfillTransportationModesJob.perform_later
    end

    source_ids = SUPPORTED_SOURCE_IDS.join(', ')
    execute("SELECT id FROM imports WHERE source IN (#{source_ids}) ORDER BY id").each_with_index do |row, index|
      TransportationModes::ImportBackfillJob.set(wait: 2.minutes + index * 10.seconds).perform_later(row['id'])
    end
  end

  def down; end
end
