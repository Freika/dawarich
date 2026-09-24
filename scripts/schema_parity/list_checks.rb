# frozen_string_literal: true

require 'json'

root = ARGV.fetch(0)
states = JSON.parse(File.read(File.join(root, 'db/release_migrations.json'))).fetch('states')
floor = states.index { _1.fetch('first_release') == '0.37.2' } or abort 'no 0.37.2 state in db/release_migrations.json'
present = Dir[File.join(root, 'db/migrate/*.rb')].filter_map { File.basename(_1)[/\A(\d+)_/, 1] }
listed = states.flat_map { _1.fetch('schema_added') }
fixtures = Dir[File.join(root, 'scripts/schema_parity/fixtures/*.sql')].map { File.basename(_1, '.sql') }.sort
tsv = File.join(root, 'scripts/schema_parity/ecto_expectations.tsv')
job = /\A(-|[A-Z]\w*(::[A-Z]\w*)*)\z/
declared = File.readlines(tsv, chomp: true).each_with_index.map do |line, index|
  check, status, detail, *rest = line.split("\t", -1)
  kind = check.to_s[/\A[a-z]+(?=:|\z)/]
  enforced =
    case kind
    when 'refused' then status == 'refused' && detail.to_s.match?(/\A\d+(\.\d+)+\z/)
    when 'contended', 'step', 'rows', 'upgrade', 'fresh'
      status.to_s.match?(/\A(ok|failed@\d{14})\z/) && detail.to_s.match?(job)
    end
  unless enforced && rest.empty?
    abort "ecto_expectations.tsv:#{index + 1}: not an expectation the harness enforces: #{line}"
  end
  [check, "ecto_expectations.tsv:#{index + 1}: #{line}"]
end
declared.group_by(&:first).each_value do |rows|
  abort "duplicate check in #{rows.map(&:last).join(' and ')}" if rows.size > 1
end
names = declared.map(&:first)

checks = %w[fresh fresh:empty]
states[(floor + 1)..].each do |state|
  checks << "step:#{state.fetch('first_release')}" if state.fetch('schema_added').intersect?(present)
end
checks << 'step:unreleased' if (present - listed).any?
fixtures.each do |fixture|
  checks << "rows:#{fixture}"
  checks << "rows:#{fixture}~shifted" unless fixture.include?('--unported-')
end
checks.concat(names.grep(/\Acontended:/))
states[floor..].each { |state| checks << "upgrade:#{state.fetch('first_release')}" }
Dir[File.join(root, 'db/release_snapshots/*.schemarb.sql.gz')].sort.each do |file|
  release = File.basename(file, '.schemarb.sql.gz')
  checks << "upgrade:#{release}.schemarb" if Gem::Version.new(release) >= Gem::Version.new('0.37.2')
end
checks.push('upgrade:0.37.2+20241030152025', 'upgrade:0.37.2@20260108192905', 'upgrade:1.3.1@20260301201446')
checks.concat(names.grep(/\Arefused:/))

declared.each do |check, where|
  abort "#{where}: the check is not in the list, so its expectation would never run" unless checks.include?(check)
end
puts checks
