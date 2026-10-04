# frozen_string_literal: true

module PhoenixTables
  SQL_FILES = Dir[Rails.root.join('app-phoenix/priv/repo/sql/*.sql')].sort.freeze
  SQL_TABLES = SQL_FILES.flat_map { |file| File.read(file).scan(/CREATE TABLE IF NOT EXISTS (phoenix\.\w+)/).flatten }
                        .freeze
  LEASES = 'CREATE TABLE IF NOT EXISTS phoenix.leases ' \
           '(name text PRIMARY KEY, holder text NOT NULL, expires_at timestamptz NOT NULL)'
  COUNTERS = 'CREATE TABLE IF NOT EXISTS phoenix.counters ' \
             '(key text PRIMARY KEY, value bigint NOT NULL, expires_at timestamptz NOT NULL)'
  ONCE_CLAIMS = 'CREATE TABLE IF NOT EXISTS phoenix.once_claims ' \
                '(key text PRIMARY KEY, expires_at timestamptz NOT NULL)'
  REGISTRATION_SETTING = 'CREATE TABLE IF NOT EXISTS phoenix.registration_setting ' \
                         '(id boolean PRIMARY KEY DEFAULT true CHECK (id), enabled boolean, ' \
                         'updated_at timestamptz NOT NULL DEFAULT statement_timestamp())'
  ACHIEVEMENT_CHECKS = 'CREATE TABLE IF NOT EXISTS phoenix.achievement_checks (user_id bigint PRIMARY KEY, ' \
                       'oldest_timestamp bigint NOT NULL, revision bigint NOT NULL, expires_at timestamptz NOT NULL)'
  ACHIEVEMENT_CHECK_REVISIONS = 'CREATE SEQUENCE IF NOT EXISTS phoenix.achievement_check_revisions'
  PHOENIX_STATE_TABLES = %w[once_claims leases achievement_checks].freeze

  def self.install_state!
    connection = ActiveRecord::Base.connection
    ['CREATE SCHEMA IF NOT EXISTS phoenix', LEASES, ONCE_CLAIMS, ACHIEVEMENT_CHECKS, ACHIEVEMENT_CHECK_REVISIONS,
     *PHOENIX_STATE_TABLES.map { "DELETE FROM phoenix.#{_1}" }].each { connection.execute(_1) }
    PhoenixSchema.reset!
  end

  def self.install!
    return if installed?

    connection = ActiveRecord::Base.connection
    install_state!
    connection.execute(COUNTERS)
    SQL_FILES.each do |file|
      File.read(file).split(";\n").map(&:strip).reject(&:empty?).each { |statement| connection.execute(statement) }
    end
  end

  def self.installed?
    connection = ActiveRecord::Base.connection
    tables = SQL_TABLES + %w[phoenix.counters] + PHOENIX_STATE_TABLES.map { "phoenix.#{_1}" }
    names = tables.map { connection.quote(_1) }.join(', ')
    connection.select_value("SELECT bool_and(to_regclass(name) IS NOT NULL) FROM unnest(ARRAY[#{names}]) name")
  end

  def self.clear!
    connection = ActiveRecord::Base.connection
    (SQL_TABLES.reverse + %w[phoenix.counters] + PHOENIX_STATE_TABLES.map { "phoenix.#{_1}" }).each do |table|
      connection.execute("DELETE FROM #{table}")
    end
    PhoenixSchema.reset!
  end

  def phoenix_tables!
    PhoenixTables.install!
  end

  def phoenix_counters!
    ActiveRecord::Base.connection.execute('CREATE SCHEMA IF NOT EXISTS phoenix')
    ActiveRecord::Base.connection.execute(COUNTERS)
  end

  def phoenix_leases!
    ActiveRecord::Base.connection.execute('CREATE SCHEMA IF NOT EXISTS phoenix')
    ActiveRecord::Base.connection.execute(LEASES)
  end

  def phoenix_state!
    phoenix_leases!
    ActiveRecord::Base.connection.execute(ONCE_CLAIMS)
    ActiveRecord::Base.connection.execute(ACHIEVEMENT_CHECKS)
    ActiveRecord::Base.connection.execute(ACHIEVEMENT_CHECK_REVISIONS)
  end

  def without_phoenix_state!
    PHOENIX_STATE_TABLES.each { |table| ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS phoenix.#{table}") }
    PhoenixSchema.reset!
  end

  def phoenix_registration!
    connection = ActiveRecord::Base.connection
    connection.execute('CREATE SCHEMA IF NOT EXISTS phoenix')
    connection.execute(REGISTRATION_SETTING)
    PhoenixSchema.reset!
  end

  def with_legacy_welcome
    connection = ActiveRecord::Base.connection
    connection.execute('DROP TABLE IF EXISTS phoenix.once_claims')
    PhoenixSchema.reset!
    yield
  ensure
    connection.execute(ONCE_CLAIMS)
    PhoenixSchema.reset!
  end

  def with_legacy_registration
    connection = ActiveRecord::Base.connection
    present = PhoenixSchema.table?('registration_setting')
    rows = connection.select_rows('SELECT id, enabled, updated_at FROM phoenix.registration_setting') if present
    connection.execute('DROP TABLE IF EXISTS phoenix.registration_setting')
    PhoenixSchema.reset!
    yield
  ensure
    if present
      phoenix_registration!
      rows.each do |row|
        sql = 'INSERT INTO phoenix.registration_setting (id, enabled, updated_at) VALUES (?, ?, ?)'
        connection.execute(ActiveRecord::Base.sanitize_sql_array(
                             [sql, *row]
                           ))
      end
    end
    PhoenixSchema.reset!
  end

  def clear_geocode_claims!
    Sidekiq.redis { |r| r.keys('geocode:enq:*').each { |k| r.del(k) } }
    ActiveRecord::Base.connection.execute("DELETE FROM phoenix.once_claims WHERE key LIKE 'geocode:enq:%'")
  end

  def claim_seconds(key)
    connection = ActiveRecord::Base.connection
    connection.select_value(
      'SELECT extract(epoch FROM expires_at - statement_timestamp()) FROM phoenix.once_claims ' \
      "WHERE key = #{connection.quote(key)}"
    )&.to_f
  end

  def expire_claim_in(key, interval)
    connection = ActiveRecord::Base.connection
    connection.execute(
      "UPDATE phoenix.once_claims SET expires_at = statement_timestamp() + interval #{connection.quote(interval)} " \
      "WHERE key = #{connection.quote(key)}"
    )
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

RSpec.configure do |config|
  config.include PhoenixTables
  config.before(:suite) do
    PhoenixTables.install!
    PhoenixTables.clear!
  end
  config.after { PhoenixSchema.reset! }
end
