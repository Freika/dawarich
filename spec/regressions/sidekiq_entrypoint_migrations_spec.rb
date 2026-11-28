# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

RSpec.describe 'Sidekiq entrypoint migrations' do
  let(:entrypoint) { File.expand_path('../../docker/sidekiq-entrypoint.sh', __dir__) }
  let(:commands) { File.readlines(File.join(@directory, 'commands'), chomp: true) }

  around do |example|
    Dir.mktmpdir do |directory|
      @directory = directory
      example.run
    end
  end

  before do
    stubs = {
      'psql' => <<~SH,
        echo psql >> "$COMMAND_LOG"
        if [ "$RETRY_DATABASE" = "true" ] && [ ! -f "$COMMAND_LOG.ready" ]; then
          touch "$COMMAND_LOG.ready"
          exit 1
        fi
      SH
      'sleep' => 'exit 0',
      'bundle' => <<~SH
        echo "bundle $*" >> "$COMMAND_LOG"
        case "$*" in
          'exec rails db:abort_if_pending_migrations')
            [ -z "$CHECK_ERROR" ] || echo "$CHECK_ERROR" >&2
            exit "${CHECK_STATUS:-0}"
            ;;
          'exec sidekiq') exit 0 ;;
          *) exit 99 ;;
        esac
      SH
    }
    stubs.each do |name, body|
      path = File.join(@directory, name)
      File.write(path, "#!/bin/sh\n#{body}\n")
      File.chmod(0o755, path)
    end
  end

  def run_entrypoint(overrides = {})
    env = {
      'PATH' => "#{@directory}:#{ENV.fetch('PATH')}",
      'COMMAND_LOG' => File.join(@directory, 'commands'),
      'PUID' => nil, 'PGID' => nil, 'DATABASE_URL' => nil,
      'RAILS_ENV' => 'production', 'BACKGROUND_PROCESSING_CONCURRENCY' => '3',
      'DATABASE_HOST' => 'example.invalid', 'DATABASE_PORT' => '5432',
      'DATABASE_USERNAME' => 'test', 'DATABASE_PASSWORD' => 'test', 'DATABASE_NAME' => 'test',
      'CHECK_STATUS' => '0', 'CHECK_ERROR' => nil, 'RETRY_DATABASE' => nil
    }
    Open3.capture3(env.merge(overrides), 'sh', entrypoint)
  end

  it 'checks migrations after connectivity and starts Sidekiq exactly once' do
    _, _, status = run_entrypoint

    expect(status).to be_success
    expect(commands).to eq(['psql', 'bundle exec rails db:abort_if_pending_migrations', 'bundle exec sidekiq'])
  end

  it 'preserves a pending migration failure and explains how to recover without starting Sidekiq' do
    _, stderr, status = run_entrypoint('CHECK_STATUS' => '1', 'CHECK_ERROR' => 'Migrations are pending')

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include('Migrations are pending', 'matching app and worker image tags',
                              'complete migrations through the app container', 'restart the worker')
    expect(commands).to eq(['psql', 'bundle exec rails db:abort_if_pending_migrations'])
  end

  it 'preserves other Rails errors and their exit status without starting Sidekiq' do
    _, stderr, status = run_entrypoint('CHECK_STATUS' => '2', 'CHECK_ERROR' => 'permission denied for schema public')

    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('permission denied for schema public')
    expect(commands).to eq(['psql', 'bundle exec rails db:abort_if_pending_migrations'])
  end

  it 'starts Sidekiq only on the restart after migrations complete' do
    _, _, failed_status = run_entrypoint('CHECK_STATUS' => '1')
    _, _, recovered_status = run_entrypoint

    expect(failed_status).not_to be_success
    expect(recovered_status).to be_success
    expect(commands).to eq(['psql', 'bundle exec rails db:abort_if_pending_migrations',
                            'psql', 'bundle exec rails db:abort_if_pending_migrations', 'bundle exec sidekiq'])
  end

  it 'waits for database connectivity before checking migrations' do
    _, _, status = run_entrypoint('RETRY_DATABASE' => 'true')

    expect(status).to be_success
    expect(commands).to eq(['psql', 'psql', 'bundle exec rails db:abort_if_pending_migrations', 'bundle exec sidekiq'])
  end
end
