# frozen_string_literal: true

ROOT = File.expand_path('../../..', __dir__)
MISSING_NAMED = 10

Shard = Struct.new(:problems, :listed, :ran, :unported, :elapsed, :reused, :computed, keyword_init: true)

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

def expected_status(check, declared)
  unported = check[/\Arows:.*--unported-([^~]+)(?:~shifted)?\z/, 1]
  unported ? "ok (unported@#{unported})" : declared.fetch(check, 'ok')
end

def locate(dir, pattern)
  Dir.glob(File.join(dir, '**', pattern)).reject { _1.include?('/ref/') }.min
end

def lines_of(path)
  path && File.file?(path) ? File.read(path, encoding: 'UTF-8').scrub.lines(chomp: true).reject(&:empty?) : []
end

def proof_record(dir)
  path = locate(dir, 'proof.env')
  path && lines_of(path).to_h { _1.split('=', 2) }
end

def harness_problem(proof)
  return 'no proof record: the proof step never ran' unless proof
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
    expected = expected_status(check, declared)
    actual == expected ? [] : ["#{check}: expected '#{expected}', actual '#{actual}'"]
  end
  [problems, listed.reject { by_check.key?(_1) }]
end

def missing_problems(missing, listed, declared, detailed)
  return [] if missing.empty?
  return ["#{missing.size} of #{listed.size} checks have no summary line"] unless detailed

  named = missing.first(MISSING_NAMED).map { "#{_1}: expected '#{expected_status(_1, declared)}', actual: no line" }
  rest = missing.size - MISSING_NAMED
  rest.positive? ? named + ["and #{rest} more checks have no summary line"] : named
end

def evaluate(dir, declared)
  proof = proof_record(dir)
  listed = lines_of(locate(dir, 'list.txt'))
  summary = locate(dir, 'summary*.txt')
  aborted, results = lines_of(summary).partition { _1.start_with?('ABORTED') }
  problems = [harness_problem(proof)].compact
  problems << 'no --list selection' if listed.empty?
  problems << 'no summary file' unless summary
  problems.concat(aborted)
  checked, missing = line_problems(listed, results, declared)
  problems.concat(checked)
  problems.concat(missing_problems(missing, listed, declared, summary && aborted.empty?))
  seen = results.map { _1.split(' ', 2).first }
  problems << 'the summary is not in --list order' if problems.empty? && seen != listed
  Shard.new(
    problems: problems, listed: listed.size, ran: (seen & listed).size,
    unported: results.grep(/ ok \(unported@/).map { _1.split(' ', 2).first },
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
  shard = Dir.exist?(dir) ? evaluate(dir, declared) : Shard.new(problems: [], listed: 0, ran: 0, unported: [])
  problems = [job_problem(job)].compact
  problems << 'no artifact: the job was cancelled, timed out or failed before its upload' unless Dir.exist?(dir)
  problems.concat(shard.problems)
  link = artifact_id ? "[#{name}](#{ENV.fetch('RUN_URL')}/artifacts/#{artifact_id})" : 'none'
  cells = [pg, number, job&.last || 'none', "#{shard.ran} / #{shard.listed}", shard.elapsed || '-',
           "#{shard.reused || '-'} / #{shard.computed || '-'}", problems.size, shard.unported.size, link]
  ["| #{cells.join(' | ')} |", problems.map { "#{name}: #{_1}" }, shard.unported.map { "#{name}: #{_1}" }]
end

def section(title, items)
  items.empty? ? [] : ['', title, '', *items.map { |item| "- #{item}" }]
end

def report(artifacts, jobs_path, artifact_ids_path)
  declared = declared_outcomes
  jobs = table_of(jobs_path)
  ids = table_of(artifact_ids_path)
  rows = ENV.fetch('LEGS').split.map { shard_row(_1, File.join(artifacts, _1), jobs[_1], ids[_1]&.first, declared) }
  failures = rows.flat_map { _1[1] }
  failures << "matrix result: #{ENV.fetch('PROVE_RESULT')}" unless ENV.fetch('PROVE_RESULT') == 'success'
  unported = rows.flat_map { _1[2] }
  puts '## Ecto nightly matrix', '', failures.empty? ? '**Pass.**' : "**Fail: #{failures.size} problems.**", ''
  puts '| PG | Shard | Job | Checks run | Elapsed | Refs reused / computed | Failures | Unported | Artifact |'
  puts '|---|---|---|---|---|---|---|---|---|', rows.map(&:first)
  puts section('### Failures', failures), section("### Declared unported effects (#{unported.size})", unported)
  puts '', "Run: #{ENV.fetch('RUN_URL')}"
  failures.empty?
end

def leg(dir)
  shard = evaluate(dir, declared_outcomes)
  shard.problems.each { puts "problem: #{_1}" }
  puts "#{shard.ran} of #{shard.listed} checks, #{shard.unported.size} unported, references " \
       "#{shard.reused || '-'} reused / #{shard.computed || '-'} computed, #{shard.problems.size} problems"
  shard.problems.empty?
end

begin
  passed =
    case ARGV[0]
    when 'report' then report(*ARGV[1, 3])
    when 'leg' then leg(ARGV.fetch(1))
    else abort 'usage: nightly_report.rb report <artifacts> <jobs.tsv> <artifacts.tsv> | leg <work dir>'
    end
  exit(passed ? 0 : 1)
rescue StandardError => e
  puts "nightly report failed: #{e.class}: #{e.message}"
  exit 1
end
