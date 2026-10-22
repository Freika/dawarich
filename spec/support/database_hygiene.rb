# frozen_string_literal: true

module DatabaseHygiene
  KEPT_TABLES = %w[schema_migrations ar_internal_metadata spatial_ref_sys].freeze

  def self.connection
    ActiveRecord::Base.connection
  end

  def self.tables
    names = connection.select_values("SELECT tablename FROM pg_tables WHERE schemaname = 'public'") - KEPT_TABLES
    names.sort.map { |name| "public.#{connection.quote_table_name(name)}" }
  end

  def self.truncate_all
    connection.execute("TRUNCATE TABLE #{tables.join(', ')} CASCADE")
  end

  def self.tables_with_rows
    tables.select { |table| connection.select_value("SELECT EXISTS (SELECT 1 FROM #{table})") }
  end
end

RSpec.configure do |config|
  config.before(:suite) { DatabaseHygiene.truncate_all }

  config.after do
    DatabaseHygiene.truncate_all unless use_transactional_tests
  end

  config.after(:suite) do
    leftovers = DatabaseHygiene.tables_with_rows
    raise "Specs left committed rows in: #{leftovers.join(', ')}" if leftovers.any?
  end
end
