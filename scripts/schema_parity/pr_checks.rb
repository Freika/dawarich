# frozen_string_literal: true

require 'json'
require 'open3'

root = File.expand_path('../..', __dir__)
listed = File.readlines(ARGV.fetch(0), chomp: true)
changed = $stdin.readlines(chomp: true)
states = JSON.parse(File.read(File.join(root, 'db/release_migrations.json'))).fetch('states')
state_of = states.each_with_object({}) do |state, map|
  state.fetch('schema_added').each { map[_1] = state.fetch('first_release') }
end
floor = states.index { _1.fetch('first_release') == '0.37.2' } or abort 'no 0.37.2 state in db/release_migrations.json'
up_to_floor = states[0..floor].flat_map { _1.fetch('schema_added') }
after_floor = ['unreleased', *states[(floor + 1)..].map { _1.fetch('first_release') }]
present = Dir[File.join(root, 'db/migrate/*.rb')].filter_map { File.basename(_1)[/\A(\d+)_/, 1] }
unreleased = present - state_of.keys
fixtures = Dir[File.join(root, 'scripts/schema_parity/fixtures/unreleased--*.sql')].map { File.basename(_1) }
inline_effects = File.readlines(File.join(root, 'scripts/schema_parity/inline_effects.tsv'), chomp: true)
                     .map { _1.split("\t") }

unless unreleased.empty?
  inventory, status = Open3.capture2('ruby', File.join(root, 'scripts/schema_parity/inventory.rb'), *unreleased)
  abort 'inventory.rb failed' unless status.success?
  missing = inventory.lines.filter_map do |line|
    _state, version, tags = line.chomp.split("\t")
    tags = tags.to_s.split(',')
    data_dependent = tags.intersect?(%w[rows validates env effect invalid]) || (%w[job gated] - tags).empty?
    version if data_dependent && fixtures.none? { _1.include?(version) }
  end
  if missing.any?
    abort "add scripts/schema_parity/fixtures/unreleased--<version>[-<variant>].sql for each of: #{missing.join(' ')}"
  end
end

machinery = %r{
  \Aapp-phoenix/lib/dawarich/(release_migrations?\.ex|release_migrator\.ex|release_migrator/|release\.ex|repo\.ex)
  |\Aapp-phoenix/lib/dawarich/active_record_encryption(\.ex\z|/)
  |\Aapp-phoenix/priv/ruby_encodings\.txt\z
  |\Aapp-phoenix/lib/dawarich/release_migrations/(?!(?:v[\d_]+|unreleased)\.ex\z)
  |\Aapp-phoenix/priv/(release_migrations/(?!(?:unreleased|[\d.]+)/)|repo/)
  |\Aapp-phoenix/test/support/mix/tasks/dawarich\.release_migrate\.ex\z
  |\Aapp-phoenix/(config/|mix\.(exs|lock)\z|\.tool-versions\z)
  |\Adb/(release_migrations\.json\z|release_snapshots/)
  |\A(\.env\.development|\.ruby-version|\.github/workflows/ecto-counterparts\.yml)\z
  |\Ascripts/schema_parity/[^/]+\z
}x
releases = ['unreleased']
modules = []
fixture_checks = []
refusals = false
changed.each do |path|
  if (version = path[%r{\Adb/migrate/(\d+)_}, 1])
    releases << state_of.fetch(version, 'unreleased')
    refusals ||= up_to_floor.include?(version)
  elsif (release = path[%r{\Aapp-phoenix/lib/dawarich/release_migrations/v([\d_]+)\.ex\z}, 1]&.tr('_', '.') ||
                   path[%r{\Aapp-phoenix/lib/dawarich/release_migrations/(unreleased)\.ex\z}, 1] ||
                   path[%r{\Aapp-phoenix/priv/release_migrations/(unreleased|[\d.]+)/}, 1])
    releases << release
    modules << release
  elsif (name = path[%r{\Ascripts/schema_parity/fixtures/([^/]+)\.(?:sql|env)\z}, 1])
    twins = listed & ["rows:#{name}", "rows:#{name}~shifted"]
    release = name[/\A([^-]+)(?:--|\z)/, 1]
    if File.exist?(File.join(root, path)) && (twins.empty? || !after_floor.include?(release))
      abort "#{path} maps to no listed check of a release after the floor (expected <release>[--<variant>])"
    end
    fixture_checks.concat(twins)
    releases << release
  end
end

inline_effects.each do |path, release|
  next unless changed.include?(path)

  releases << release
  modules << release
end

older_than_a_module = lambda do |check|
  start = check[/\Aupgrade:(\d+(?:\.\d+)*)/, 1] or next false
  modules.any? { _1 == 'unreleased' || Gem::Version.new(start) < Gem::Version.new(_1) }
end
migrator_gems = %w[rails activerecord activesupport activemodel railties pg strong_migrations data_migrate oj json]
migrator_gems_bumped = changed.include?('Gemfile.lock') && begin
  range = ARGV[1].to_s
  abort 'Gemfile.lock changed: pass the diff range <base>...<head> as the second argument' if range.empty?
  lock_diff, status = Open3.capture2('git', '-C', root, 'diff', '--no-color', '--no-ext-diff', '--no-renames', range,
                                     '--', 'Gemfile.lock')
  abort "git diff #{range} -- Gemfile.lock failed" unless status.success?
  lock_diff.match?(/^[-+] {4}(?:#{migrator_gems.join('|')}) \(/)
end
full = migrator_gems_bumped || changed.any? { _1.match?(machinery) }
picked = listed.select do |check|
  release = check[/\A(?:step|rows|contended):([^:~]+?)(?:--|~|:|\z)/, 1]
  full || (release && releases.include?(release)) || fixture_checks.include?(check) ||
    (refusals && check.start_with?('refused:')) || older_than_a_module.call(check)
end
puts(['fresh', *picked].uniq)
