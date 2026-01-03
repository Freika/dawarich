# Generated from Rails Pulse schema - automatically loads current schema definition
class InstallRailsPulseTables < ActiveRecord::Migration[8.0]
  def change
    # Load and execute the Rails Pulse schema directly
    # This ensures the migration is always in sync with the schema file
    schema_file = Rails.root.join('db/rails_pulse_schema.rb').to_s

    raise 'Rails Pulse schema file not found at db/rails_pulse_schema.rb' unless File.exist?(schema_file)

    say 'Loading Rails Pulse schema from db/rails_pulse_schema.rb'

    # Load the schema file to define RailsPulse::Schema
    load schema_file

    # Execute the schema in the context of this migration
    RailsPulse::Schema.call(connection)

    say 'Rails Pulse tables created successfully'
    say 'The schema file db/rails_pulse_schema.rb remains as your single source of truth'
  end
end
