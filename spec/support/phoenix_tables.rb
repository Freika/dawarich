# frozen_string_literal: true

module PhoenixTables
  SQL_FILES = Dir[Rails.root.join('app-phoenix/priv/repo/sql/*.sql')].sort.freeze

  def phoenix_tables!
    connection = ActiveRecord::Base.connection
    return if connection.select_value("SELECT to_regclass('phoenix.notification_events') IS NOT NULL")

    connection.execute('CREATE SCHEMA IF NOT EXISTS phoenix')
    SQL_FILES.each do |file|
      File.read(file).split(";\n").map(&:strip).reject(&:empty?).each { |statement| connection.execute(statement) }
    end
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
