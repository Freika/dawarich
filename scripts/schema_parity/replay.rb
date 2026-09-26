# frozen_string_literal: true

tag = ARGV.fetch(0)
paths = SchemaParity::GitTags.files_at(tag)
schema = SchemaParity::ReleaseMap.versions(paths, 'db/migrate').map(&:to_i)
data = SchemaParity::ReleaseMap.versions(paths, 'db/data')

context = ActiveRecord::Base.connection_pool.migration_context
schema.each { |version| context.run(:up, version) }

unless data.empty?
  connection = ActiveRecord::Base.connection
  connection.execute('CREATE TABLE IF NOT EXISTS data_migrations (version varchar PRIMARY KEY)')
  data.each do |version|
    connection.execute(
      "INSERT INTO data_migrations (version) VALUES (#{connection.quote(version)}) ON CONFLICT DO NOTHING"
    )
  end
end

puts "replayed #{schema.size} schema and recorded #{data.size} data migrations for #{tag}"
