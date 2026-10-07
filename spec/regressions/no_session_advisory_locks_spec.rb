# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Session-level advisory locks behind PgBouncer transaction pooling' do
  let(:sources) { Dir[Rails.root.join('{app,lib,app-phoenix/lib}/**/*.{rb,rake,ex}')].sort }
  let(:allowed_session_gem_locks) { %w[app/services/phoenix_lease.rb] }
  let(:allowed_session_modules) do
    {
      'app-phoenix/lib/dawarich/cloud/session_connection.ex' =>
        'Cloud L1 leases use a dedicated direct Postgrex connection that refuses transaction pooling'
    }
  end

  def relative(path) = Pathname(path).relative_path_from(Rails.root).to_s

  def without_migrator_lock(path)
    source = File.read(path)
    return source unless relative(path) == 'app-phoenix/lib/dawarich/release/native.ex'

    migration = source[/  def with_lock\(repo, opts, fun\) do\n.*?(?=  def classify!)/m]
    expect(migration).to include('if Dawarich.Visits.Persister.advisory_locks?(env["DATABASE_ADVISORY_LOCKS"]) do',
                                 'Postgrex.start_link(config ++ [backoff_type: :stop, max_restarts: 0])',
                                 'key = 2_053_462_845 * :erlang.crc32(database)',
                                 'if Process.alive?(conn), do: GenServer.stop(conn)',
                                 "    else\n      fun.()\n    end")
    calls = migration.scan(/Postgrex.query!\(\s*conn,\s*"(SELECT pg_[^"]+)"/)
    expect(calls.flatten).to match_array(['SELECT pg_advisory_lock($1)',
                                          'SELECT pg_advisory_unlock($1), pg_advisory_unlock($1)',
                                          'SELECT pg_try_advisory_lock($1)'])
    expect(migration.scan(/pg_(?:try_)?advisory_(?:lock|unlock)\(\$1\)/).size).to eq(4)
    expect(migration).to include('repo.config()', 'SELECT current_database()::text',
                                 'acquire_lock(conn, key, opts, deadline)', ').rows == [[true, true]]')
    source.sub(migration, migration.gsub(/pg_(try_)?advisory_(lock|unlock)\(\$1\)/, 'migrator_lock'))
  end

  def session_lock_offenders(paths)
    paths.select do |path|
      !allowed_session_modules.key?(relative(path)) &&
        without_migrator_lock(path).match?(/pg_(try_)?advisory_(lock|unlock)(_shared|_all)?\s*\(/i)
    end
  end

  it 'allows only dedicated direct-connection session locks in Rails or Phoenix code' do
    offenders = session_lock_offenders(sources)
    expect(offenders.map { relative(_1) }).to be_empty
  end

  it 'rejects legal session-lock spellings outside the dedicated Cloud exception', :aggregate_failures do
    path = Rails.root.join('app-phoenix/lib/dawarich/audit_probe.ex').to_s
    allowed_path = Rails.root.join(allowed_session_modules.keys.fetch(0)).to_s
    calls = [
      'pg_advisory_lock(123)',
      'pg_advisory_lock (123)',
      'PG_ADVISORY_LOCK(123)',
      "pg_advisory_lock\n(123)",
      'pg_catalog.pg_advisory_lock(123)',
      "PG_CATALOG.PG_TRY_ADVISORY_LOCK_SHARED \n(123)",
      'pg_advisory_unlock (123)',
      'pg_advisory_unlock_shared (123)',
      'pg_advisory_unlock_all ()'
    ]

    calls.each do |call|
      source = %(repo.query!("SELECT #{call}"))
      allow(File).to receive(:read).with(path).and_return(source)
      allow(File).to receive(:read).with(allowed_path).and_return(source)

      expect(session_lock_offenders([path, allowed_path])).to eq([path]), call
    end

    %w[pg_advisory_xact_lock pg_try_advisory_xact_lock pg_advisory_xact_lock_shared].each do |function|
      allow(File).to receive(:read).with(path).and_return(%(repo.query!("SELECT #{function} (123)")))
      expect(session_lock_offenders([path])).to be_empty, function
    end
  end

  it 'takes gem or Rails advisory locks only transaction-scoped, outside the listed files' do
    call = /\b(?:with_advisory_lock(?:_result)?!?|get_advisory_lock)(?=[\s(])/
    offenders = sources.select do |path|
      File.readlines(path).any? { |line| line.match?(call) && !line.include?('transaction: true') }
    end
    expect(offenders.map { relative(_1) }).to eq(allowed_session_gem_locks)
  end
end
