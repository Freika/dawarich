# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

RSpec.describe 'Phoenix lifecycle entrypoints' do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:stubs) { Dir.mktmpdir('phoenix-lifecycle') }
  let(:calls_file) { File.join(stubs, 'calls.log') }
  let(:server) { ['puma', '-C', 'config/puma.rb', '-p', '5000', '--tag', 'two words'] }

  after { FileUtils.remove_entry(stubs) }

  before do
    %w[createdb psql].each { |name| stub_command(name, 'exit 0') }
    stub_command('id', 'echo 1000')
    stub_command('bundle', %(printf '%s\\n' "bundle $*" >> "#{calls_file}"))
    stub_command('dawarich', <<~SH)
      if [ "$1" = start ]; then
        printf '%s\\n' "dawarich start $(printf '%s' "$DAWARICH_RAILS_ARGS" | tr '\\037' '|')" >> "#{calls_file}"
        exit 0
      fi
      printf '%s\\n' "dawarich $*" >> "#{calls_file}"
      case "$1" in
        migrate) exit "${STUB_MIGRATE_STATUS:-0}" ;;
        seeds) exit "${STUB_SEEDS_STATUS:-0}" ;;
        eval) exit "${STUB_READY_STATUS:-0}" ;;
      esac
    SH
  end

  def stub_command(name, body)
    path = File.join(stubs, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  def run_script(name, *args, **env)
    FileUtils.rm_f(calls_file)
    base = {
      'PATH' => "#{stubs}:#{ENV.fetch('PATH')}", 'APP_PATH' => stubs, 'RAILS_ENV' => 'test',
      'PUID' => nil, 'PGID' => nil, 'DATABASE_URL' => nil, 'DATABASE_HOST' => '127.0.0.1',
      'DATABASE_NAME' => 'dawarich_test_a12h', 'DATABASE_PASSWORD' => '',
      'DAWARICH_PHOENIX_LIFECYCLE' => 'true', 'SELF_HOSTED' => 'true'
    }
    _, stderr, status = Open3.capture3(base.merge(env.transform_keys(&:to_s)), 'sh',
                                       File.join(root, 'docker', name), *args)
    calls = File.exist?(calls_file) ? File.readlines(calls_file, chomp: true) : []
    { stderr:, status:, calls: }
  end

  it 'native web boot runs migrate then seeds then Phoenix with original server argv' do
    result = run_script('web-entrypoint.sh', *server)
    expect(result[:status]).to be_success
    expect(result[:calls]).to eq([
                                   'dawarich migrate', 'dawarich seeds',
                                   'dawarich eval Dawarich.Release.halt_unless_ready()',
                                   'dawarich start bundle|exec|puma|-C|config/puma.rb|-p|5000|--tag|two words|'
                                 ])
  end

  it 'self-hosted native release runs migration and seeds without Rails tasks' do
    result = run_script('release.sh')
    expect(result[:status]).to be_success
    expect(result[:calls]).to eq(['dawarich migrate', 'dawarich seeds'])
    %w[STUB_MIGRATE_STATUS STUB_SEEDS_STATUS].each do |failure|
      result = run_script('release.sh', **{ failure => '7' })
      expect(result[:status].exitstatus).to eq(7)
      expected = failure == 'STUB_MIGRATE_STATUS' ? ['dawarich migrate'] : ['dawarich migrate', 'dawarich seeds']
      expect(result[:calls]).to eq(expected)
    end
  end

  it 'Cloud native lifecycle refuses before either migrator runs' do
    %w[release.sh web-entrypoint.sh].each do |script|
      result = run_script(script, *server, SELF_HOSTED: 'false')
      expect(result[:status]).not_to be_success
      expect(result[:stderr]).to include('requires self-hosted mode')
      expect(result[:calls]).to be_empty
    end
  end

  it 'native web boot stops on migration or seed failure' do
    [server, ['bin/rails', 'runner', 'puts 1']].each do |argv|
      %w[STUB_MIGRATE_STATUS STUB_SEEDS_STATUS].each do |failure|
        result = run_script('web-entrypoint.sh', *argv, **{ failure => '7' })
        expect(result[:status].exitstatus).to eq(7)
        expected = failure == 'STUB_MIGRATE_STATUS' ? ['dawarich migrate'] : ['dawarich migrate', 'dawarich seeds']
        expect(result[:calls]).to eq(expected)
      end
    end
    [nil, 'false'].each do |flag|
      expect(run_script('web-entrypoint.sh', *server, DAWARICH_PHOENIX_LIFECYCLE: flag)[:status]).to be_success
    end
    ['', 'yes', 'TRUE'].each do |flag|
      result = run_script('web-entrypoint.sh', *server, DAWARICH_PHOENIX_LIFECYCLE: flag)
      expect(result[:status]).not_to be_success
      expect(result[:calls]).to be_empty
    end
  end
end
