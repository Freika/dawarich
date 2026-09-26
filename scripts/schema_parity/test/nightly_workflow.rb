# frozen_string_literal: true

require 'open3'
require 'psych'

root = File.expand_path('../../..', __dir__)
path = ARGV.fetch(0) { File.join(root, '.github/workflows/ecto-nightly.yml') }
text = File.read(path)
workflow = Psych.safe_load(text)
@failures = 0

def check(label)
  if yield
    puts "ok - #{label}"
  else
    puts "not ok - #{label}"
    @failures += 1
  end
rescue StandardError => e
  puts "not ok - #{label} (#{e.class}: #{e.message})"
  @failures += 1
end

triggers = workflow['on'] || workflow[true]
jobs = workflow.fetch('jobs')
prove = jobs.fetch('prove')
report = jobs.fetch('report')
steps = prove.fetch('steps')
step = ->(name) { steps.find { _1['name'].to_s.start_with?(name) } or raise "no step #{name}" }
index = ->(name) { steps.index(step.call(name)) }
matrix = prove.dig('strategy', 'matrix')

check('the workflow parses and runs on a schedule and on manual dispatch only') do
  triggers.keys.sort == %w[schedule workflow_dispatch]
end
check('the schedule is one daily cron entry away from the top of the hour') do
  crons = triggers['schedule'].map { _1['cron'] }
  minute, hour, *rest = crons.first.split
  crons.size == 1 && minute.match?(/\A\d+\z/) && !%w[0 00].include?(minute) && hour.match?(/\A\d+\z/) &&
    rest == %w[* * *]
end
check('the workflow token is read-only') { workflow['permissions'] == { 'contents' => 'read' } }
check('only a newer run of the same ref cancels a run') do
  workflow['concurrency'] == { 'group' => 'ecto-nightly-${{ github.ref }}', 'cancel-in-progress' => true }
end
check('the matrix is PostgreSQL 14 and 17 by two shards, all reporting') do
  matrix == { 'pg' => [14, 17], 'shard' => [1, 2] } && prove.dig('strategy', 'fail-fast') == false &&
    prove.dig('strategy', 'max-parallel') == 4
end
check('each shard job has a 180-minute limit on ubuntu-latest') do
  prove['timeout-minutes'] == 180 && prove['runs-on'] == 'ubuntu-latest'
end
check('SHARDS matches the matrix') { workflow.dig('env', 'SHARDS') == matrix['shard'].size }
check('the job name is the artifact name and the report expects exactly those legs') do
  legs = matrix['pg'].product(matrix['shard']).map { |pg, shard| "pg#{pg}-shard#{shard}" }
  prove['name'] == 'pg${{ matrix.pg }}-shard${{ matrix.shard }}' &&
    step.call('Upload the shard').dig('with', 'name') == prove['name'] && report.dig('env', 'LEGS').split == legs
end
check('the harness gets the server major and shard from the matrix') do
  prove['env'].slice('SP_PG_MAJOR', 'SHARD', 'LANG') ==
    { 'SP_PG_MAJOR' => '${{ matrix.pg }}', 'SHARD' => '${{ matrix.shard }}', 'LANG' => 'en_US.UTF-8' }
end
check('Ruby comes from .ruby-version and OTP/Elixir from app-phoenix/.tool-versions') do
  step.call('Set up Ruby')['with'] == { 'bundler-cache' => true } &&
    step.call('Set up Elixir')['with'] == { 'version-file' => 'app-phoenix/.tool-versions', 'version-type' => 'strict' }
end
check('every action is pinned to a commit with its version in a comment') do
  uses = text.lines.grep(/^\s*(?:- )?uses:/)
  uses.any? && uses.all? { _1.match?(%r{uses: [\w.-]+/[\w./-]+@[0-9a-f]{40} # v\d+(\.\d+)*$}) }
end
check('no step is allowed to fail softly and no secret is used') do
  !text.include?('continue-on-error') && !text.include?('secrets.')
end
check('the servers start and are checked before the preflight, which runs before the proof') do
  index.call('Start PostgreSQL') < index.call('Check the server') &&
    index.call('Check the server') < index.call('Check the matrix inventory') &&
    index.call('Check the matrix inventory') < index.call('Prove shard')
end
check('the proof runs the shard wrapper and the summary is compared even when it fails') do
  step.call('Prove shard')['run'].strip == 'scripts/schema_parity/ci/prove_shard.sh' &&
    step.call('Compare the summary')['if'] == 'always()'
end
check('the reference cache holds only tmp/schema_parity/ecto/ref under one exact key per major and shard') do
  restore = step.call('Restore the Rails references')
  save = step.call('Save the Rails references')
  key = step.call('Key the Rails reference cache')['run']
  cache = { 'path' => 'tmp/schema_parity/ecto/ref', 'key' => '${{ steps.key.outputs.key }}' }
  [restore, save].all? { _1['with'] == cache } &&
    key.include?('pg$SP_PG_MAJOR-shard$SHARD-of-$SHARDS') && key.include?('v$REF_CACHE_FORMAT') &&
    !text.include?('restore-keys')
end
check('the references are saved only after a green shard and never over an existing entry') do
  step.call('Save the Rails references')['if'] ==
    "steps.prove.outcome == 'success' && steps.verify.outcome == 'success' && steps.restore.outputs.cache-hit != 'true'"
end
check('the evidence is uploaded on success and failure without the references') do
  upload = step.call('Upload the shard')
  paths = upload.dig('with', 'path').split("\n")
  upload['if'] == 'always()' && paths.none? { _1.include?('ecto/ref') } &&
    %w[summary prove.log diffs inventory_preflight nightly/].all? { |part| paths.any? { _1.include?(part) } }
end
check('the report runs after every shard, whatever happened, with read-only access to the run') do
  report['needs'] == 'prove' && report['if'] == 'always()' &&
    report['permissions'] == { 'actions' => 'read', 'contents' => 'read' } &&
    report.dig('env', 'PROVE_RESULT') == '${{ needs.prove.result }}'
end
check('every report step after the download runs even when the download fails') do
  report['steps'].drop_while { !_1['name'].start_with?('Download') }.drop(1).all? { _1['if'] == 'always()' }
end
check('every run block is valid bash') do
  blocks = jobs.values.flat_map { _1['steps'] }.filter_map { _1['run'] }
  blocks.all? do |block|
    _out, err, status = Open3.capture3('bash', '-n', stdin_data: block.gsub(/\$\{\{[^}]*\}\}/, 'X'))
    status.success? || (warn(err) && false)
  end
end

puts "#{@failures} failed"
exit(@failures.zero? ? 0 : 1)
