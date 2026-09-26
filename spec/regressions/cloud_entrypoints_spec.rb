# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

RSpec.describe 'Cloud entrypoints' do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:stubs) { Dir.mktmpdir('cloud-entrypoints') }
  let(:calls_file) { File.join(stubs, 'calls.log') }
  let(:psql_count) { File.join(stubs, 'psql.count') }
  let(:server) { %w[puma -C config/puma.rb -p 5000] }

  after { FileUtils.remove_entry(stubs) }

  before do
    stub_command('id', 'echo 1000')
    stub_command('psql', <<~SH)
      printf '%s\\n' "psql[${PGCONNECT_TIMEOUT:-}] PGPASSWORD=${PGPASSWORD:-} $*" >> "#{calls_file}"
      n=$(($(cat "#{psql_count}" 2>/dev/null || echo 0) + 1))
      echo "$n" > "#{psql_count}"
      [ "$n" -gt "${STUB_PSQL_FAILURES:-0}" ]
    SH
    stub_command('sleep', 'exit 0')
    stub_command('bundle', %(printf '%s\\n' "bundle $*" >> "#{calls_file}"; exit "${STUB_BUNDLE_STATUS:-0}"))
    stub_command('dawarich', <<~SH)
      if [ "$1" = start ]; then
        printf '%s\\n' "dawarich start $(printf '%s' "$DAWARICH_RAILS_ARGS" | tr '\\037' '|')" >> "#{calls_file}"
        exit 0
      fi
      printf '%s\\n' "dawarich $1 $2" >> "#{calls_file}"
      exit "${STUB_DAWARICH_STATUS:-0}"
    SH
  end

  def stub_command(name, body)
    path = File.join(stubs, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  def run_script(name, *args, **env)
    base = {
      'PATH' => "#{stubs}:#{ENV.fetch('PATH')}",
      'APP_PATH' => stubs,
      'RAILS_ENV' => 'production',
      'PUID' => nil,
      'PGID' => nil,
      'BUNDLE_PATH' => nil,
      'BUNDLE_BIN' => nil,
      'DATABASE_URL' => nil,
      'DATABASE_HOST' => 'db',
      'DATABASE_PORT' => '6432',
      'DATABASE_USERNAME' => 'app',
      'DATABASE_PASSWORD' => 'secret',
      'DATABASE_NAME' => 'dawarich'
    }
    _, stderr, status = Open3.capture3(base.merge(env.transform_keys(&:to_s)), 'sh',
                                       File.join(root, 'docker', name), *args)
    calls = File.exist?(calls_file) ? File.readlines(calls_file, chomp: true) : []
    { stderr:, status:, calls:, app_calls: calls.grep_v(/\Apsql\[/), psql: calls.grep(/\Apsql\[/) }
  end

  describe 'release.sh' do
    it 'runs the Rails schema migrations, then the Phoenix migrations, and nothing else' do
      result = run_script('release.sh')

      expect(result[:status]).to be_success
      expect(result[:app_calls]).to eq(['bundle exec rails db:migrate', 'dawarich eval Dawarich.Release.migrate()'])
    end

    it 'succeeds with a warning when the Phoenix migrations fail' do
      result = run_script('release.sh', STUB_DAWARICH_STATUS: '1')

      expect(result[:status]).to be_success
      expect(result[:stderr]).to include('Phoenix migrations failed')
    end

    it 'fails before the Phoenix migrations when the Rails migrations fail' do
      result = run_script('release.sh', STUB_BUNDLE_STATUS: '1')

      expect(result[:status]).not_to be_success
      expect(result[:app_calls]).to eq(['bundle exec rails db:migrate'])
    end

    it 'gives up on the database after 60 silent attempts and one visible one' do
      result = run_script('release.sh', STUB_PSQL_FAILURES: '1000')

      expect(result[:status]).not_to be_success
      expect(result[:psql].size).to eq(61)
      expect(result[:psql]).to all(eq('psql[5] PGPASSWORD=secret -h db -p 6432 -U app -d dawarich -c SELECT 1'))
      expect(result[:app_calls]).to be_empty
    end
  end

  describe 'cloud-entrypoint.sh' do
    it 'starts the server under Phoenix when its schemas are ready' do
      result = run_script('cloud-entrypoint.sh', *server)

      expect(result[:app_calls]).to eq(
        ['dawarich eval Dawarich.Release.halt_unless_ready()',
         'dawarich start bundle|exec|puma|-C|config/puma.rb|-p|5000|']
      )
    end

    {
      '3' => 'Phoenix schemas are missing, unreadable or behind this image',
      '4' => 'the Erlang cookie file cannot be read',
      '5' => 'PostgreSQL did not answer the Phoenix readiness check',
      '1' => 'the Phoenix readiness check failed with exit status 1'
    }.each do |status, cause|
      it "starts Rails alone and names the cause when the readiness check exits #{status}" do
        result = run_script('cloud-entrypoint.sh', *server, STUB_DAWARICH_STATUS: status)

        expect(result[:app_calls]).to eq(
          ['dawarich eval Dawarich.Release.halt_unless_ready()', 'bundle exec puma -C config/puma.rb -p 5000']
        )
        expect(result[:stderr]).to include("#{cause}; starting Rails without the Phoenix supervisor")
      end
    end

    it 'runs any other command directly, without Phoenix' do
      result = run_script('cloud-entrypoint.sh', 'bin/rails', 'runner', 'puts 1')

      expect(result[:app_calls]).to eq(['bundle exec bin/rails runner puts 1'])
    end
  end

  describe 'cloud-sidekiq-entrypoint.sh' do
    it 'waits for the database, then runs the given command' do
      result = run_script('cloud-sidekiq-entrypoint.sh', 'sidekiq', '-C', 'config/sidekiq.yml')

      expect(result[:calls]).to eq(
        ['psql[5] PGPASSWORD=secret -h db -p 6432 -U app -d dawarich -c SELECT 1',
         'bundle exec sidekiq -C config/sidekiq.yml']
      )
    end
  end

  %w[cloud-entrypoint.sh cloud-sidekiq-entrypoint.sh].each do |script|
    it "#{script} keeps waiting for the database past 60 attempts" do
      result = run_script(script, 'true', STUB_PSQL_FAILURES: '70')

      expect(result[:psql].size).to eq(71)
      expect(result[:app_calls]).to eq(['bundle exec true'])
    end
  end

  describe 'bootstrap' do
    %w[release.sh cloud-entrypoint.sh cloud-sidekiq-entrypoint.sh].each do |script|
      [nil, '', 'development'].each do |rails_env|
        it "#{script} refuses to start with RAILS_ENV=#{rails_env.inspect}" do
          result = run_script(script, 'true', RAILS_ENV: rails_env)

          expect(result[:status].exitstatus).to eq(1)
          expect(result[:stderr]).to include('RAILS_ENV')
          expect(result[:calls]).to be_empty
        end
      end

      it "#{script} runs Bundler without the buildpack's BUNDLE_PATH and BUNDLE_BIN" do
        stub_command('bundle', %(printf '%s\\n' "bundle ${BUNDLE_PATH-unset} ${BUNDLE_BIN-unset}" >> "#{calls_file}"))

        result = run_script(script, 'true', BUNDLE_PATH: '/app/vendor/bundle', BUNDLE_BIN: '/app/vendor/bundle/bin')

        expect(result[:calls].grep(/\Abundle /)).to eq(['bundle unset unset'])
      end
    end
  end

  describe 'dropping root' do
    before do
      FileUtils.mkdir_p([File.join(stubs, 'tmp'), File.join(stubs, 'storage')])
      stub_command('id', 'echo 0')
      stub_command('chown', %(printf '%s\\n' "chown $*" >> "#{calls_file}"))
      stub_command('gosu', %(printf '%s\\n' "gosu $*" >> "#{calls_file}"))
    end

    %w[release.sh cloud-entrypoint.sh cloud-sidekiq-entrypoint.sh].each do |script|
      it "#{script} hands tmp and storage to 32767 and re-runs itself as that user before anything else" do
        result = run_script(script, 'x')

        expect(result[:calls]).to eq(
          ["chown -R 32767:32767 #{stubs}/tmp",
           "chown -R 32767:32767 #{stubs}/storage",
           "gosu 32767:32767 env HOME=#{stubs}/tmp #{File.join(root, 'docker', script)} x"]
        )
      end
    end

    it 'leaves directories alone that the target user already owns' do
      owner = Process.uid.zero? ? 1000 : Process.uid
      FileUtils.chown(owner, nil, [File.join(stubs, 'tmp'), File.join(stubs, 'storage')])

      result = run_script('cloud-entrypoint.sh', 'x', PUID: owner.to_s, PGID: Process.gid.to_s)

      expect(result[:calls]).to eq(
        ["gosu #{owner}:#{Process.gid} env HOME=#{stubs}/tmp #{File.join(root, 'docker/cloud-entrypoint.sh')} x"]
      )
    end

    %w[0 root].each do |puid|
      it "refuses PUID=#{puid}, which would keep re-running itself as root" do
        result = run_script('cloud-entrypoint.sh', 'x', PUID: puid)

        expect(result[:status].exitstatus).to eq(1)
        expect(result[:stderr]).to include("uid '#{puid}'")
        expect(result[:calls]).to be_empty
      end
    end
  end

  describe 'wait_for_database' do
    it 'hands DATABASE_URL to psql with the postgis scheme rewritten' do
      result = run_script('release.sh', DATABASE_URL: 'postgis://app:p%40ss@db:6432/dawarich?sslmode=disable')

      expect(result[:psql].first).to eq(
        'psql[5] PGPASSWORD=secret postgres://app:p%40ss@db:6432/dawarich?sslmode=disable -c SELECT 1'
      )
    end
  end

  describe 'is_server_command' do
    def server_command?(*args)
      _, _, status = Open3.capture3('sh', '-c', '. "$0"; is_server_command "$@"',
                                    File.join(root, 'docker/entrypoint-common.sh'), *args)
      status.success?
    end

    it 'matches the Rails and Puma server commands and nothing else' do
      expect(server_command?('bin/rails', 'server', '-p', '3000', '-b', '::')).to be(true)
      expect(server_command?('puma', '-C', 'config/puma.rb')).to be(true)
      expect(server_command?('bin/rails', 'runner', 'x')).to be(false)
      expect(server_command?('sidekiq')).to be(false)
    end
  end

  it 'shares the server hand-off with the self-hosted web entrypoint' do
    web = File.read(File.join(root, 'docker/web-entrypoint.sh'))

    expect(web).to include('. "$(dirname "$0")/entrypoint-common.sh"')
    expect(web).to include('exec_under_phoenix "$@"')
    expect(web).not_to include('DAWARICH_RAILS_ARGS')
  end

  it 'defines the Cloud web health check with the keys Dokku reads and no predeploy migration' do
    cloud = JSON.parse(File.read(File.join(root, 'app.cloud.json')))
    check = cloud.dig('healthchecks', 'web', 0)

    expect(check).to include('type' => 'startup', 'path' => '/api/v1/health', 'port' => 5000,
                             'attempts' => 10, 'wait' => 10)
    expect(check).not_to have_key('interval')
    expect(cloud).not_to have_key('scripts')
  end
end
