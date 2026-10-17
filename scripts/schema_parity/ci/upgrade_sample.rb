# frozen_string_literal: true

require 'json'
require_relative '../snapshot_paths'

ROOT = File.expand_path('../../..', __dir__)

begin
  listed = File.readlines(ARGV.fetch(0), chomp: true)
  states = JSON.parse(File.read(File.join(ROOT, 'db/release_migrations.json'))).fetch('states')
  newest = states.last&.fetch('first_release') or abort 'upgrade sample: db/release_migrations.json has no state'
  sample = ['upgrade:0.37.2', "upgrade:#{newest}", 'upgrade:1.0.1.schemarb', 'upgrade:0.37.2@20260108192905']
  snapshots = File.join(ROOT, 'db/release_snapshots')
  absent = sample.filter_map do |check|
    next "#{check} is not in ecto_prove.sh --list" unless listed.include?(check)

    paths = snapshot_paths(check.delete_prefix('upgrade:'), snapshots)
    "#{check} has no #{paths.map { File.basename(_1) }.join(' or ')}" if paths.none? { File.exist?(_1) }
  end
  if absent.any?
    abort "upgrade sample: #{absent.join('; ')}. Restore it or change the sample in " \
          'scripts/schema_parity/ci/upgrade_sample.rb'
  end
  puts sample
rescue StandardError => e
  abort "upgrade sample: #{e.class}: #{e.message}"
end
