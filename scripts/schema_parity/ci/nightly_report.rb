# frozen_string_literal: true

ROOT = File.expand_path('../../..', __dir__)
MISSING_NAMED = 10

Shard = Struct.new(:problems, :checks, :ran, :elapsed, :reused, :computed, keyword_init: true)

def declared_outcomes
  File.readlines(File.join(ROOT, 'scripts/schema_parity/ecto_expectations.tsv'), chomp: true).to_h do |line|
    check, status, detail = line.split("\t", -1)
    outcome =
      case status
      when 'refused' then "ok (refused below_floor #{detail})"
      when 'ok' then 'ok'
      else "ok (#{status})"
      end
    [check, outcome]
  end
end

def matches(dir, pattern)
  Dir.glob(File.join(dir, '**', pattern)).reject { _1.include?('/ref/') }.sort
end

def only(found, pattern, problems)
  problems << "#{found.size} files match #{pattern}: #{found.map { File.basename(_1) }.join(', ')}" if found.size > 1
  found.first if found.size == 1
end

def sample(items)
  shown = items.first(MISSING_NAMED).join(', ')
  items.size > MISSING_NAMED ? "#{shown} and #{items.size - MISSING_NAMED} more" : shown
end

def lines_of(path)
  path && File.file?(path) ? File.read(path, encoding: 'UTF-8').scrub.lines(chomp: true).reject(&:empty?) : []
end

def harness_problem(proof)
  return 'no proof record: the proof step never ran' unless proof
  return 'the proof step stopped before the harness exited (nightly/proof.env has no exit)' unless proof.key?('exit')
  return if proof['exit'] == '0'
  return 'the harness timed out (GNU timeout, exit 124)' if proof['exit'] == '124'

  "the harness exited #{proof['exit']}"
end

def line_problems(listed, results, declared)
  by_check = results.group_by { _1.split(' ', 2).first }
  problems = by_check.flat_map do |check, group|
    next ["#{check}: not in the --list selection (#{group.first})"] unless listed.include?(check)
    next ["#{check}: #{group.size} summary lines"] if group.size > 1

    actual = group.first.split(' ', 2)[1].to_s
    expected = declared.fetch(check, 'ok')
    actual == expected ? [] : ["#{check}: expected '#{expected}', actual '#{actual}'"]
  end
  [problems, listed.reject { by_check.key?(_1) }]
end

def missing_problems(missing, listed, declared, detailed)
  return [] if missing.empty?
  return ["#{missing.size} of #{listed.size} checks have no summary line"] unless detailed

  named = missing.first(MISSING_NAMED).map { "#{_1}: expected '#{declared.fetch(_1, 'ok')}', actual: no line" }
  rest = missing.size - MISSING_NAMED
  rest.positive? ? named + ["and #{rest} more checks have no summary line"] : named
end

def evaluate(dir, declared)
  problems = []
  proof_path = only(matches(dir, 'proof.env'), 'proof.env', problems)
  proof = proof_path && lines_of(proof_path).to_h { _1.split('=', 2) }
  listed = lines_of(only(matches(dir, 'list.txt'), 'list.txt', problems))
  summaries = matches(dir, 'summary*.txt')
  summary = only(summaries, 'summary*.txt', problems)
  aborted, results = lines_of(summary).partition { _1.start_with?('ABORTED') }
  preflight = lines_of(only(matches(dir, 'inventory_preflight.out'), 'inventory_preflight.out', problems))
  problems.concat(preflight.grep(/\Amatrix inventory preflight: (?!ok,)/))
  problems << harness_problem(proof) if harness_problem(proof)
  problems << 'no --list selection' if listed.empty?
  problems << 'no summary file' if summaries.empty?
  problems.concat(aborted)
  checked, missing = line_problems(listed, results, declared)
  problems.concat(checked)
  problems.concat(missing_problems(missing, listed, declared, summary && aborted.empty?))
  seen = results.map { _1.split(' ', 2).first }
  problems << 'the summary is not in --list order' if problems.empty? && seen != listed
  Shard.new(
    problems: problems, checks: listed, ran: (seen & listed).size,
    elapsed: proof && elapsed(proof), reused: (proof['refs_reused'] if proof && proof['exit'] == '0'),
    computed: proof&.fetch('refs_computed', nil)
  )
end

def elapsed(proof)
  seconds = Integer(proof.fetch('finished')) - Integer(proof.fetch('started'))
  format('%<h>d:%<m>02d:%<s>02d', h: seconds / 3600, m: seconds % 3600 / 60, s: seconds % 60)
rescue KeyError, ArgumentError
  nil
end

def table_of(path)
  lines_of(path).to_h do |line|
    name, *rest = line.split("\t")
    [name, rest]
  end
end

def job_problem(job)
  return 'no job result' unless job
  return if job == %w[completed success]

  "job #{job.join(', ')}"
end

def shard_row(name, dir, job, artifact_id, declared)
  pg, number = name.match(/\Apg(\d+)-shard(\d+)\z/)&.captures || [name, '?']
  shard = Dir.exist?(dir) ? evaluate(dir, declared) : Shard.new(problems: [], checks: [], ran: 0)
  problems = [job_problem(job)].compact
  problems << 'no artifact: the job was cancelled, timed out or failed before its upload' unless Dir.exist?(dir)
  problems.concat(shard.problems)
  link = artifact_id ? "[#{name}](#{ENV.fetch('RUN_URL')}/artifacts/#{artifact_id})" : 'none'
  cells = [pg, number, job&.last || 'none', "#{shard.ran} / #{shard.checks.size}", shard.elapsed || '-',
           "#{shard.reused || '-'} / #{shard.computed || '-'}", problems.size, link]
  ["| #{cells.join(' | ')} |", problems.map { "#{name}: #{_1}" }, shard.checks]
end

def coverage_problems(legs, lists, full)
  return ['no full check list (scripts/schema_parity/list_checks.rb failed or was not run)'] if full.empty?

  legs.group_by { _1[/\Apg(\d+)-/, 1] || _1 }.flat_map do |major, names|
    owners = Hash.new { |hash, check| hash[check] = [] }
    names.each { |name| lists.fetch(name).each { owners[_1] << name } }
    uncovered = full - owners.keys
    shared = owners.select { |_, shards| shards.size > 1 }.map { |check, shards| "#{check} (#{shards.join(', ')})" }
    unknown = owners.keys - full
    problems = []
    problems << "#{uncovered.size} of #{full.size} checks are in no shard: #{sample(uncovered)}" if uncovered.any?
    problems << "#{count(shared, 'check is', 'checks are')} in more than one shard: #{sample(shared)}" if shared.any?
    if unknown.any?
      problems << "#{count(unknown, 'shard check is', 'shard checks are')} not in the full check list: " \
                  "#{sample(unknown)}"
    end
    problems.map { "pg#{major}: #{_1}" }
  end
end

def count(items, one, many)
  "#{items.size} #{items.size == 1 ? one : many}"
end

def section(title, items)
  items.empty? ? [] : ['', title, '', *items.map { |item| "- #{item}" }]
end

def report(artifacts, jobs_path, artifact_ids_path, checks_path)
  declared = declared_outcomes
  jobs = table_of(jobs_path)
  ids = table_of(artifact_ids_path)
  legs = ENV.fetch('LEGS').split
  rows = legs.map { shard_row(_1, File.join(artifacts, _1), jobs[_1], ids[_1]&.first, declared) }
  failures = rows.flat_map { _1[1] }
  failures.concat(coverage_problems(legs, legs.zip(rows.map(&:last)).to_h, lines_of(checks_path)))
  failures << "matrix result: #{ENV.fetch('PROVE_RESULT')}" unless ENV.fetch('PROVE_RESULT') == 'success'
  puts '## Ecto nightly matrix', '', failures.empty? ? '**Pass.**' : "**Fail: #{failures.size} problems.**", ''
  puts '| PG | Shard | Job | Checks run | Elapsed | Refs reused / computed | Failures | Artifact |'
  puts '|---|---|---|---|---|---|---|---|', rows.map(&:first)
  puts section('### Failures', failures)
  puts '', "Run: #{ENV.fetch('RUN_URL')}"
  failures.empty?
end

def leg(dir)
  shard = evaluate(dir, declared_outcomes)
  shard.problems.each { puts "problem: #{_1}" }
  puts "#{shard.ran} of #{shard.checks.size} checks, references " \
       "#{shard.reused || '-'} reused / #{shard.computed || '-'} computed, #{shard.problems.size} problems"
  shard.problems.empty?
end

begin
  passed =
    case ARGV[0]
    when 'report' then report(*ARGV[1, 4])
    when 'leg' then leg(ARGV.fetch(1))
    else abort 'usage: nightly_report.rb report <artifacts> <jobs.tsv> <artifacts.tsv> <checks.txt> | leg <work dir>'
    end
  exit(passed ? 0 : 1)
rescue StandardError => e
  puts "nightly report failed: #{e.class}: #{e.message}"
  exit 1
end
