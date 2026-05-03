# frozen_string_literal: true

class DropRailsPulseTables < ActiveRecord::Migration[8.0]
  TABLES = %w[
    rails_pulse_operations
    rails_pulse_summaries
    rails_pulse_requests
    rails_pulse_queries
    rails_pulse_routes
  ].freeze

  def up
    TABLES.each { |t| drop_table t, if_exists: true, force: :cascade }
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'rails_pulse has been removed from the project; reinstall the gem to recreate these tables.'
  end
end
