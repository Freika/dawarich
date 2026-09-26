# frozen_string_literal: true

require 'open3'
require 'psych'

root = File.expand_path('../../..', __dir__)
path = ARGV.fetch(0) { File.join(root, '.github/workflows/ecto-counterparts.yml') }
text = File.read(path)
workflow = Psych.safe_load(text)
nightly = File.read(File.join(root, '.github/workflows/ecto-nightly.yml'))
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

PIN = %r{uses: ([\w.-]+/[\w./-]+)@([0-9a-f]{40} # v\d+(?:\.\d+)*)$}
triggers = workflow['on'] || workflow[true]
jobs = workflow.fetch('jobs')
sample = jobs.fetch('ecto-upgrade-sample', {})
tests = jobs.fetch('harness-tests', {})
docker_tests = jobs.fetch('harness-docker-tests', {})
steps = sample.fetch('steps', [])
step = ->(name) { steps.find { _1['name'].to_s.start_with?(name) } or raise "no step #{name}" }
index = ->(name) { steps.index(step.call(name)) }
test_runs = tests.fetch('steps', []).filter_map { _1['run'] }

check('pull requests and pushes to dev and master trigger every job, with no path filter') do
  triggers.keys.sort == %w[pull_request push] && triggers['pull_request'].nil? &&
    triggers['push'] == { 'branches' => %w[master dev] }
end
check('every action is pinned to a commit with its version in a comment') do
  uses = text.lines.grep(/^\s*(?:- )?uses:/)
  uses.any? && uses.all? { _1.match?(PIN) }
end
check('every action shared with ecto-nightly.yml uses the same commit and version') do
  theirs = nightly.scan(PIN).to_h
  shared = text.scan(PIN).select { theirs.key?(_1.first) }
  shared.any? && shared.size == text.scan(PIN).size && shared.all? { |action, pin| theirs[action] == pin }
end
check("C2's change-driven selection stays in the ecto-counterparts job") do
  selection, *rest = jobs.fetch('ecto-counterparts').fetch('steps').drop_while { _1['id'] != 'select' }
  selection['run'].include?('| ruby scripts/schema_parity/pr_checks.rb "$RUNNER_TEMP/list.txt" "$BASE_SHA...HEAD" ' \
                            '> "$RUNNER_TEMP/checks.txt"') &&
    rest.any? { _1['run'].to_s.include?('ecto_prove.sh --jobs 2 $(cat "$RUNNER_TEMP/checks.txt")') }
end
check('the upgrade sample runs once per PostgreSQL major, every leg reporting') do
  sample.dig('strategy', 'matrix') == { 'pg' => [14, 17] } && sample.dig('strategy', 'fail-fast') == false &&
    sample['runs-on'] == 'ubuntu-latest' && sample['timeout-minutes'].is_a?(Integer)
end
check('each leg names its major and hands it and the locale to the harness') do
  sample['name'] == 'upgrade sample pg${{ matrix.pg }}' &&
    sample['env'].slice('SP_PG_MAJOR', 'LANG') == { 'SP_PG_MAJOR' => '${{ matrix.pg }}', 'LANG' => 'en_US.UTF-8' }
end
check('the sample comes from the authoritative --list through the selector') do
  run = step.call('Select the upgrade sample')['run']
  run.include?('scripts/schema_parity/ecto_prove.sh --list > "$RUNNER_TEMP/list.txt"') &&
    run.include?('ruby scripts/schema_parity/ci/upgrade_sample.rb "$RUNNER_TEMP/list.txt" > "$RUNNER_TEMP/sample.txt"')
end
check('the server starts after the selection and before the proof, which runs the shard wrapper on the sample') do
  index.call('Select the upgrade sample') < index.call('Start PostgreSQL') &&
    index.call('Start PostgreSQL') < index.call('Prove the upgrade sample') &&
    step.call('Start PostgreSQL')['run'].strip == 'scripts/schema_parity/infra.sh up' &&
    step.call('Prove the upgrade sample')['run'].strip ==
      'exec scripts/schema_parity/ci/prove_shard.sh $(cat "$RUNNER_TEMP/sample.txt")'
end
check('the summary needs one ok line per sampled check and no unported result, compared even after a failure') do
  verify = step.call('Compare the summary')
  verify['if'] == 'always()' && verify['id'] == 'verify' &&
    verify['run'].include?('ruby scripts/schema_parity/ci/nightly_report.rb leg tmp/schema_parity') &&
    verify['run'].include?("grep -F 'unported@' tmp/schema_parity/ecto/summary.txt")
end
check('the reference cache holds only tmp/schema_parity/ecto/ref under one exact key per major') do
  cache = { 'path' => 'tmp/schema_parity/ecto/ref', 'key' => '${{ steps.select.outputs.key }}' }
  key = step.call('Select the upgrade sample')['run']
  parts = %w[ecto-ref-sample-v$REF_CACHE_FORMAT pg$SP_PG_MAJOR ${ImageOS ci/ref_cache_key.sh] + ['date -u +%G-W%V']
  [step.call('Restore the Rails references'), step.call('Save the Rails references')].all? { _1['with'] == cache } &&
    parts.all? { key.include?(_1) } && !text.include?('restore-keys') &&
    sample.dig('env', 'REF_CACHE_FORMAT').is_a?(Integer)
end
check('the references are saved only after a green sample and never over an existing entry') do
  step.call('Save the Rails references')['if'] ==
    "steps.prove.outcome == 'success' && steps.verify.outcome == 'success' && steps.restore.outputs.cache-hit != 'true'"
end
check('the evidence is uploaded on success and failure under a name unique to the major, without the references') do
  upload = step.call('Upload the sample')
  paths = upload.dig('with', 'path').split("\n")
  upload['if'] == 'always()' && upload.dig('with', 'name') == 'upgrade-sample-pg${{ matrix.pg }}' &&
    paths.none? { _1.include?('ecto/ref') } &&
    %w[summary.txt prove.log diffs nightly/].all? { |part| paths.any? { _1.include?(part) } }
end
check('the harness self-tests run every test under scripts/schema_parity/test/ except the Docker one') do
  wanted = Dir[File.join(root, 'scripts/schema_parity/test/*')].map { File.basename(_1) } - ['pg_major.sh']
  wanted.any? && wanted.all? do |name|
    runner = name.end_with?('.rb') ? 'ruby' : 'sh'
    test_runs.any? { _1.strip == "#{runner} scripts/schema_parity/test/#{name}" }
  end
end
check('the harness self-tests need no Docker, no Bundler and no path filter, under the UTF-8 locale') do
  ruby = tests['steps'].find { _1['uses'].to_s.start_with?('ruby/setup-ruby@') }
  ruby && !ruby.fetch('with', {}).key?('bundler-cache') && tests.dig('env', 'LANG') == 'en_US.UTF-8' &&
    test_runs.none? { _1.match?(/docker|infra\.sh|pg_major|bundle/) } && !tests.key?('services') &&
    !tests.key?('needs') && !tests.key?('if')
end
check('pg_major.sh runs in its own Docker job') do
  docker_tests.fetch('steps').filter_map { _1['run'] }.map(&:strip) == ['sh scripts/schema_parity/test/pg_major.sh'] &&
    docker_tests.dig('env', 'LANG') == 'en_US.UTF-8'
end
check('no step is allowed to fail softly and no secret is used') do
  !text.include?('continue-on-error') && !text.include?('secrets.')
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
