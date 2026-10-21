# frozen_string_literal: true

require 'json'
require 'prism'

root = File.expand_path('../..', __dir__)
states = JSON.parse(File.read(File.join(root, 'db/release_migrations.json'))).fetch('states')
state_of = states.each_with_object({}) do |state, map|
  state.fetch('schema_added').each { map[_1] = state.fetch('first_release') }
end
floor = states.index { _1.fetch('first_release') == '0.37.2' }
floor_versions = states[0..floor].flat_map { _1.fetch('schema_added') }
tags = {
  'rows' => /
    \b(UPDATE|DELETE\s+FROM|INSERT\s+INTO|TRUNCATE)\b
    |\.(update_all|delete_all|update_columns?|insert_all|upsert_all|destroy_all|save!?|create!?|update!|destroy!?)\b
    |connection\.(update|delete|insert)\b|Flipper\.
  /x,
  'validates' => /
    validate_foreign_key|validate_check_constraint|change_column_null|VALIDATE\ CONSTRAINT|SET\ NOT\ NULL|raise
  /xi,
  'job' => /perform_later|perform_all_later/,
  'gated' => /select_value|select_values|select_all|\.exists\?|EXISTS\s*\(/,
  'effect' => /
    perform_now|Achievements::LoadRegions|Achievements::MigrateExplorationState
    |Geocoding::SeedFromEnv|InstanceSettings::Backfill
  /x,
  'env' => /ENV\b|DawarichSettings|backfill_allowed\?|ActiveStorage::Blob\.service/,
  'notx' => /disable_ddl_transaction!/,
  'lockretry' => /LockWaitTimeout/,
  'rescue' => /rescue ActiveRecord::(RecordNotUnique|StatementInvalid)/,
  'sessionset' => /execute\s*\(?\s*['"](SET|RESET)\s+(?!LOCAL)/i,
  'invalid' => /indisvalid/
}
wanted = ARGV
Dir[File.join(root, 'db/migrate/*.rb')].sort.each do |path|
  version = File.basename(path)[/\A(\d+)_/, 1] or next
  next if floor_versions.include?(version)
  next unless wanted.empty? || wanted.include?(version)

  source = File.read(path, encoding: 'utf-8')
  cuts = []
  walk = lambda do |node|
    next unless node

    node.is_a?(Prism::DefNode) && node.name == :down ? cuts << node.location : node.compact_child_nodes.each(&walk)
  end
  walk.call(Prism.parse(source).value)
  cuts.sort_by { -_1.start_offset }.each { |cut| source.bytesplice(cut.start_offset...cut.end_offset, '') }
  body = source.lines.grep_v(/^\s*#/).join
  flagged = tags.select { |_, pattern| body.match?(pattern) }.keys.join(',')
  puts [state_of[version] || 'unreleased', version, flagged].join("\t")
end
