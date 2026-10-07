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

  it 'allows only dedicated direct-connection session locks in Rails or Phoenix code' do
    offenders = sources.select do |path|
      !allowed_session_modules.key?(relative(path)) &&
        without_migrator_lock(path).match?(/pg_(try_)?advisory_(lock|unlock)(_shared|_all)?\(/i)
    end
    expect(offenders.map { relative(_1) }).to be_empty
  end

  it 'takes gem or Rails advisory locks only transaction-scoped, outside the listed files' do
    call = /\b(?:with_advisory_lock(?:_result)?!?|get_advisory_lock)(?=[\s(])/
    offenders = sources.select do |path|
      File.readlines(path).any? { |line| line.match?(call) && !line.include?('transaction: true') }
    end
    expect(offenders.map { relative(_1) }).to eq(allowed_session_gem_locks)
  end
end
