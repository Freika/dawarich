# frozen_string_literal: true

module PhoenixTables
  SQL_FILES = Dir[Rails.root.join('app-phoenix/priv/repo/sql/*.sql')].sort.freeze
  LEASES = 'CREATE TABLE IF NOT EXISTS phoenix.leases ' \
           '(name text PRIMARY KEY, holder text NOT NULL, expires_at timestamptz NOT NULL)'
  ONCE_CLAIMS = 'CREATE TABLE IF NOT EXISTS phoenix.once_claims ' \
                '(key text PRIMARY KEY, expires_at timestamptz NOT NULL)'
  ACHIEVEMENT_CHECKS = 'CREATE TABLE IF NOT EXISTS phoenix.achievement_checks (user_id bigint PRIMARY KEY, ' \
                       'oldest_timestamp bigint NOT NULL, revision bigint NOT NULL, expires_at timestamptz NOT NULL)'
  PHOENIX_STATE_TABLES = %w[once_claims leases achievement_checks].freeze

  def phoenix_tables!
    connection = ActiveRecord::Base.connection
    phoenix_leases!
    SQL_FILES.each do |file|
      File.read(file).split(";\n").map(&:strip).reject(&:empty?).each { |statement| connection.execute(statement) }
    end
  end

  def phoenix_leases!
    ActiveRecord::Base.connection.execute('CREATE SCHEMA IF NOT EXISTS phoenix')
    ActiveRecord::Base.connection.execute(LEASES)
  end

  def phoenix_state!
    phoenix_leases!
    ActiveRecord::Base.connection.execute(ONCE_CLAIMS)
    ActiveRecord::Base.connection.execute(ACHIEVEMENT_CHECKS)
  end

  def without_phoenix_state!
    PHOENIX_STATE_TABLES.each { |table| ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS phoenix.#{table}") }
  end

  def job_owner!(key, owner, pinned: false)
    phoenix_tables!
    sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, key, owner.to_s, pinned])
      INSERT INTO phoenix.job_owners (key, owner, pinned, updated_at, updated_by) VALUES (?, ?, ?, now(), 'spec')
      ON CONFLICT (key) DO UPDATE SET owner = EXCLUDED.owner, pinned = EXCLUDED.pinned
    SQL
    ActiveRecord::Base.connection.execute(sql)
  end
end

RSpec.configure { |config| config.include PhoenixTables }
