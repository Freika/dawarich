# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require_relative 'inventory_tags'

LANG_ENV = { 'LANG' => 'en_US.UTF-8' }.freeze
SCHEMARB_HEADER = %w[blob state releases result diff_lines snapshot note].freeze
SCHEMARB_RESULTS = %w[identical differs unloadable].freeze

def capture!(env, *cmd)
  out, err, status = Open3.capture3(env, *cmd)
  abort "matrix inventory preflight: #{cmd.join(' ')} failed: #{err}#{out}" unless status.success?

  out
end

def snapshot_paths(label, snapshots_dir)
  if label.end_with?('.schemarb')
    [File.join(snapshots_dir, "#{label.delete_suffix('.schemarb')}.schemarb.sql.gz")]
  else
    release = label.split(/[@+]/, 2).first
    %w[image replay].map { |kind| File.join(snapshots_dir, "#{release}.#{kind}.sql.gz") }
  end
end

def release_fixtures(fixtures, release)
  if release == 'unreleased'
    fixtures.select { |f| f.start_with?('unreleased--') }
  else
    fixtures.select { |f| f == "#{release}.sql" || f.start_with?("#{release}--") }
  end
end

def fixture_covers?(fixtures, release, version)
  candidates = release_fixtures(fixtures, release)
  release == 'unreleased' ? candidates.any? { |f| f.include?(version) } : candidates.any?
end

def data_migration_covered?(fixtures, release, version)
  release_fixtures(fixtures, release).any? { |f| f.include?(version) }
end

def schemarb_rows(snapshots_dir)
  lines = File.readlines(File.join(snapshots_dir, 'schemarb.tsv'), chomp: true)
  header = lines.shift.to_s.split("\t", -1)
  unless header == SCHEMARB_HEADER
    abort "matrix inventory preflight: schemarb.tsv header is #{header.inspect}, expected #{SCHEMARB_HEADER.inspect}"
  end

  lines.map do |line|
    columns = line.split("\t", -1)
    unless columns.size == SCHEMARB_HEADER.size
      abort "matrix inventory preflight: schemarb.tsv row has #{columns.size} columns, expected " \
            "#{SCHEMARB_HEADER.size}: #{line}"
    end

    row = SCHEMARB_HEADER.zip(columns).to_h
    unless SCHEMARB_RESULTS.include?(row['result'])
      abort "matrix inventory preflight: schemarb.tsv result #{row['result'].inspect} is not one of " \
            "#{SCHEMARB_RESULTS.inspect}: #{line}"
    end

    row
  end
end

def main(root)
  snapshots_dir = File.join(root, 'db/release_snapshots')
  fixtures_dir = File.join(root, 'scripts/schema_parity/fixtures')
  checks = capture!(LANG_ENV, File.join(root, 'scripts/schema_parity/ecto_prove.sh'), '--list').lines(chomp: true)

  states = JSON.parse(File.read(File.join(root, 'db/release_migrations.json'))).fetch('states')
  floor_index = states.index { |s| s.fetch('first_release') == '0.37.2' } or
    abort 'matrix inventory preflight: no 0.37.2 state in db/release_migrations.json'
  supported_states = states[floor_index..]
  supported_releases = supported_states.map { |s| s.fetch('first_release') }

  supported_states.each do |state|
    release = state.fetch('first_release')
    check = "upgrade:#{release}"
    abort "matrix inventory preflight: #{check} is missing from ecto_prove.sh --list" unless checks.include?(check)

    paths = snapshot_paths(release, snapshots_dir)
    next if paths.any? { File.exist?(_1) }

    abort "matrix inventory preflight: supported state #{release} has no snapshot " \
          "(expected #{paths.map { File.basename(_1) }.join(' or ')} in db/release_snapshots/)"
  end

  schemarb_rows(snapshots_dir).each do |row|
    next unless row['result'] == 'differs'

    release = row['snapshot'].delete_suffix('.schemarb.sql.gz')
    next unless supported_releases.include?(release)

    path = File.join(snapshots_dir, row['snapshot'])
    unless File.exist?(path)
      abort "matrix inventory preflight: schema.rb variant #{row['snapshot']} is declared in schemarb.tsv but " \
            'missing from db/release_snapshots/'
    end

    check = "upgrade:#{release}.schemarb"
    abort "matrix inventory preflight: #{check} is missing from ecto_prove.sh --list" unless checks.include?(check)
  end

  File.readlines(File.join(root, 'scripts/schema_parity/ecto_expectations.tsv'), chomp: true).each do |line|
    check = line.split("\t", 2).first
    next unless check.start_with?('refused:')

    label = check.delete_prefix('refused:')
    paths = snapshot_paths(label, snapshots_dir)
    unless paths.any? { File.exist?(_1) }
      names = paths.map { File.basename(_1) }.join(' or ')
      abort "matrix inventory preflight: #{check} needs a snapshot (expected #{names} in db/release_snapshots/)"
    end

    abort "matrix inventory preflight: #{check} is missing from ecto_prove.sh --list" unless checks.include?(check)
  end

  fixtures = Dir.children(fixtures_dir).select { |f| f.end_with?('.sql') }

  capture!(LANG_ENV, 'ruby', File.join(root, 'scripts/schema_parity/inventory.rb')).each_line(chomp: true) do |line|
    release, version, tags = line.split("\t")
    tags = tags.to_s.split(',')
    next unless data_dependent?(tags)
    next if fixture_covers?(fixtures, release, version)

    abort "matrix inventory preflight: migration #{version} (#{release}, tags: #{tags.join(',')}) has no fixture " \
          'under scripts/schema_parity/fixtures'
  end

  supported_states.each do |state|
    release = state.fetch('first_release')
    state.fetch('data_added').each do |version|
      next if data_migration_covered?(fixtures, release, version)

      abort "matrix inventory preflight: data migration #{version} (#{release}) has no fixture under " \
            'scripts/schema_parity/fixtures'
    end
  end

  sp_work = ENV['SP_WORK']
  sp_work = File.join(root, 'tmp/schema_parity') if sp_work.to_s.empty?
  FileUtils.mkdir_p(sp_work)
  counts = checks.group_by { |c| c[/\A[a-z]+/] }.transform_values(&:size).sort.to_h
  artifact = File.join(sp_work, 'inventory_preflight.txt')
  File.write(artifact, <<~TXT)
    total #{checks.size}
    #{counts.map { |kind, count| "#{kind} #{count}" }.join("\n")}

    #{checks.join("\n")}
  TXT

  puts "matrix inventory preflight: ok, #{checks.size} checks (#{counts.map { |k, v| "#{v} #{k}" }.join(', ')}); " \
       "artifact at #{artifact}"
end

begin
  main(ARGV.fetch(0) { File.expand_path('../..', __dir__) })
rescue StandardError => e
  abort "matrix inventory preflight: #{e.class}: #{e.message}"
end
