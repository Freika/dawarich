# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require_relative 'a12e_fixture_support'

RSpec.describe 'Phoenix fixture: operator commands against the Rails rake tasks and console recipes' do
  include ActiveSupport::Testing::TimeHelpers

  fx = A12eFixtureSupport
  recorded = {}
  touched = "updated_at > timestamp '2026-06-01' AS touched"
  reset = 'reset_password_token IS NULL AS no_reset_token, reset_password_sent_at IS NULL AS no_reset_sent_at'
  users = { 'users' => "SELECT id, email, status, admin, #{reset}, #{touched} FROM users ORDER BY id" }
  points = { 'points' => 'SELECT p.id, p.raw_data, p.raw_data_archived, a.month, a.chunk_number, ' \
                         "p.#{touched} FROM points p LEFT JOIN points_raw_data_archives a " \
                         'ON a.id = p.raw_data_archive_id ORDER BY p.id' }
  archives = { 'archives' => 'SELECT user_id, year, month, chunk_number, point_count, point_ids_checksum, ' \
                             "verified_at IS NOT NULL AS verified, metadata - 'content_checksum' AS metadata " \
                             'FROM points_raw_data_archives ORDER BY user_id, year, month, chunk_number' }
  blobs = { 'blobs' => 'SELECT b.key, b.filename, b.content_type, a.record_type FROM active_storage_blobs b ' \
                       'JOIN active_storage_attachments a ON a.blob_id = b.id ORDER BY b.key' }
  raw = points.merge(archives, blobs)
  relative = { 'points_raw_data_archives' => %w[archived_at verified_at] }

  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?('points:raw_data:status') }

  around do |example|
    sequences = (fx::SEQUENCES - %w[phoenix.rails_commands]).to_h do |table|
      name = fx.conn.select_value("SELECT pg_get_serial_sequence(#{fx.conn.quote(table)},'id')")
      [name, fx.conn.select_rows("SELECT last_value,is_called FROM #{name}").first]
    end
    travel_to(fx::NOW) { example.run }
  ensure
    sequences&.each { |name, (value, called)| fx.sql('SELECT setval(?::regclass,?,?)', name, value, called) }
  end

  before do
    allow(OpenSSL::Cipher).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |cipher| cipher.define_singleton_method(:random_iv) { self.iv = "\0" * iv_len } }
    end
    allow(Zlib::GzipWriter).to receive(:new).and_wrap_original do |original, *args, **opts|
      original.call(*args, **opts).tap { |gzip| gzip.mtime = fx::NOW.to_i }
    end
    phoenix_tables!
    fx.reset!
    fx.sql('DELETE FROM oban.oban_jobs') if fx.conn.data_source_exists?('oban.oban_jobs')
  end

  after(:all) { fx.finish(recorded) }

  define_method(:keep) do |name, entry|
    if fx.write?
      recorded[name] = entry
    else
      stored = fx.stored(name.start_with?('A12h') ? 'seeds' : 'cli')['cases'].find { |c| c['name'] == name }
      expect(fx.comparable(entry.merge('name' => name))).to eq(fx.comparable(stored))
    end
  end

  define_method(:activation_users) do
    fx.user!(1001, 'inactive@example.invalid', status: 0)
    fx.user!(1002, 'trial@example.invalid', status: 2)
    fx.user!(1003, 'deleted@example.invalid', status: 0, deleted: true)
  end

  def capture_places_cli
    fx = A12eFixtureSupport
    outputs = {}
    %w[dawarich:backfill_place_names dawarich:cleanup_suggested_places].each do |task|
      rows = []
      [0, 103].each do |count|
        fx.reset!
        count.times { |index| fx.user!(97_800 + index, "places-cli-#{index}@example.test") }
        fx.user!(97_999, 'places-cli-deleted@example.test', deleted: true) if count.positive?
        fx.sql('CLUSTER users USING users_pkey')
        clear_enqueued_jobs
        out, err, code = fx.rake(task)
        jobs = enqueued_jobs.map do |job|
          { job: job[:job].name, args: job[:args], queue: job[:queue],
            delay: job[:at] && (job[:at] - fx::NOW.to_f).round(6) }
        end
        expected = task.end_with?('backfill_place_names') ? 1 : count
        expect(code).to eq(0)
        expect(jobs.size).to eq(expected)
        expect([out, err]).to eq(['', ''])
        if task.end_with?('cleanup_suggested_places')
          expect(jobs.map { _1[:args] }).to eq((97_800...97_800 + count).map { [_1] })
          expect(jobs.map { _1[:delay] }).to eq(count.times.map { (_1 * 0.1).round(6) })
        end
        rows << { argv: [task], count:, stdout: out, stderr: err, exit: code, jobs: }
        clear_enqueued_jobs
        out, err, code = fx.rake(task, 'ignored-extra')
        expect(code).to eq(0)
        rows << { argv: [task, 'ignored-extra'], count:, stdout: out, stderr: err, exit: code,
                  jobs: enqueued_jobs.map { { job: _1[:job].name, args: _1[:args], queue: _1[:queue] } } }
      end
      fx.reset!
      fx.user!(97_800, 'places-cli-error@example.test')
      RSpec::Mocks.with_temporary_scope do
        if task.end_with?('backfill_place_names')
          allow(Places::BulkNameFetchingJob).to receive(:perform_later).and_raise(RuntimeError,
                                                                                  'synthetic enqueue failure')
        else
          allow(User).to receive(:in_batches).and_raise(ActiveRecord::StatementInvalid, 'synthetic SQL failure')
        end
        clear_enqueued_jobs
        out, err, code = fx.rake(task)
        expect(code).to eq(1)
        expect(err).to include('synthetic')
        expect(enqueued_jobs).to be_empty
        rows << { argv: [task], failure: true, stdout: out, stderr: err, exit: code, jobs: [] }
      end
      if task.end_with?('cleanup_suggested_places')
        fx.reset!
        103.times { |index| fx.user!(97_800 + index, "places-cli-partial-#{index}@example.test") }
        fx.sql('CLUSTER users USING users_pkey')
        clear_enqueued_jobs
        calls = 0
        RSpec::Mocks.with_temporary_scope do
          allow_any_instance_of(Places::OrphanCleanupJob).to receive(:enqueue)
            .and_wrap_original do |original, *args, **options|
            calls += 1
            raise 'synthetic second-batch enqueue failure' if calls == 101

            original.call(*args, **options)
          end
          out, err, code = fx.rake(task)
          expect(code).to eq(1)
          expect(enqueued_jobs.size).to eq(100)
          rows << { argv: [task], partial_failure: true, stdout: out, stderr: err, exit: code,
                    jobs: enqueued_jobs.map do
                      { job: _1[:job].name, args: _1[:args],
                                          delay: (_1[:at] - fx::NOW.to_f).round(6) }
                    end }
        end
      end
      outputs[task.end_with?('backfill_place_names') ? '07' : '08'] = rows
    end
    fx.reset!
    fx.user!(97_800, 'places-orphan@example.test')
    rows = []
    [nil, '', 'Keep note'].each_with_index do |note, index|
      Place.insert!({ id: 978_000 + index, user_id: 97_800, name: 'Suggested', source: Place.sources[:photon],
                      latitude: 51.3397, longitude: 12.3734,
                      lonlat: 'POINT(12.373468 51.339700)', note:, created_at: fx::NOW, updated_at: fx::NOW })
      stdout = StringIO.new
      stderr = StringIO.new
      code = fx.capture(stdout, stderr, nil) do
        puts Place.where(source: :photon, note: [nil, '']).where.missing(:visits, :taggings).count
      end
      out = stdout.string
      err = stderr.string
      expect(code).to eq(0)
      expect(out.to_i).to eq(index.zero? ? 1 : 2)
      rows << { recipe: 'Place.where(source: :photon, note: [nil, ""]).where.missing(:visits, :taggings).count',
                note:, stdout: out, stderr: err, exit: code }
    end
    RSpec::Mocks.with_temporary_scope do
      allow(Place).to receive(:where).and_raise(ActiveRecord::StatementInvalid, 'synthetic orphan SQL failure')
      stdout = StringIO.new
      stderr = StringIO.new
      code = fx.capture(stdout, stderr, nil) do
        puts Place.where(source: :photon, note: [nil, '']).where.missing(:visits, :taggings).count
      end
      expect(code).to eq(1)
      rows << { recipe: 'orphan count', failure: true, stdout: stdout.string, stderr: stderr.string, exit: code }
    end
    outputs['09'] = rows
    outputs['10'] = { backfill: outputs['07'], cleanup: outputs['08'],
                      aliases: ['dawarich:backfill_place_names', 'dawarich:cleanup_suggested_places'] }
    outputs.each do |id, cases|
      path = Rails.root.join("app-phoenix/test/fixtures/places/a12f3a-p#{id}.json")
      FixtureRecording.source_verify(path, "#{JSON.pretty_generate(cases)}\n")
    end
    fx.reset!
  end

  it 'number_to_human_size' do
    expect(fx.human_sizes).to eq(fx.stored['human_sizes']) unless fx.write?
    capture_places_cli
  end

  it 'users:activate' do
    activation_users
    keep('users_activate', fx.record(argv: ['users:activate'], after: users) { fx.rake('users:activate') })
  end

  it 'users:activate on Cloud' do
    activation_users
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    keep('users_activate_cloud', fx.record(argv: ['users:activate'], env: { 'SELF_HOSTED' => 'false' },
                                           after: users) { fx.rake('users:activate') })
  end

  it 'FAQ recipe: make a user an admin' do
    fx.user!(1011, 'admin-me@example.invalid', reset: true)
    entry = fx.record(argv: %w[users admin admin-me@example.invalid], after: users, stdout: false) do
      fx.recipe { User.find_by(email: 'admin-me@example.invalid').update(admin: true) }
    end
    keep('users_admin_recipe', entry)
  end

  it 'FAQ recipe: change an email' do
    fx.user!(1021, 'old@example.invalid', reset: true)
    fx.user!(1022, 'other@example.invalid', reset: true)
    entry = fx.record(argv: ['users', 'email', 'old@example.invalid', '  New@Example.INVALID '], after: users,
                      stdout: false) do
      fx.recipe { User.find_by(email: 'old@example.invalid').update(email: '  New@Example.INVALID ') }
    end
    keep('users_email_recipe', entry)
  end

  it 'FAQ recipe: set a password' do
    fx.user!(1031, 'login@example.invalid', reset: true)
    login = { 'users' => "SELECT id, encrypted_password LIKE '$2a$%' AS bcrypt, #{reset}, #{touched} " \
                         'FROM users ORDER BY id' }
    entry = fx.record(argv: %w[users password login@example.invalid], stdin: "#{fx::LOGIN}\n", after: login,
                      stdout: false) do
      fx.recipe do
        User.find_by(email: 'login@example.invalid').update(password: fx::LOGIN, password_confirmation: fx::LOGIN)
      end
    end
    keep('users_password_recipe', entry)
  end

  it 'dawarich:jobs:status without the owner table' do
    keep('jobs_status_absent', fx.record(argv: ['dawarich:jobs:status'], drop: ['phoenix.job_owners'], after: {}) do
      fx.rake('dawarich:jobs:status')
    end)
  end

  define_method(:job_rows) do
    fx.sql("INSERT INTO phoenix.job_owners VALUES ('cron:z_job', 'sidekiq', true, '2026-01-02 03:04:05.678+00', " \
           "'rake:ops'), ('command:a.job', 'oban', false, '2026-01-01 00:00:00+00', 'phoenix')")
    fx.sql("INSERT INTO phoenix.runtime_nodes VALUES ('dawarich@a', '2026-01-01 00:00:00+00', ?)",
           '2099-01-01 00:00:00+00')
    fx.sql('INSERT INTO job_outbox (event_id, command_type, command_version, payload, scheduled_at, state, ' \
           'created_at) VALUES ' \
           "('00000000-0000-4000-8000-000000000001', 'trips.calculate', 1, '{}', " \
           "'2099-01-01 00:00:00+00', 'pending', '2026-01-01 00:00:00+00'), " \
           "('00000000-0000-4000-8000-000000000002', 'trips.calculate', 1, '{}', " \
           "'2026-01-01 00:00:00+00', 'quarantined', '2026-01-01 00:00:00+00')")
    fx.sql('INSERT INTO phoenix.rails_commands (id, kind, available_at, created_at) VALUES ' \
           "(1, 'tracks.realtime', '2099-01-01 00:00:00+00', '2026-01-01 00:00:00+00')")
    fx.sql("INSERT INTO phoenix.rails_commands_dead VALUES (7, 'tracks.realtime', '{}', 3, 'boom', " \
           "'2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')")
  end

  it 'dawarich:jobs:status with owners, nodes, outbox and reverse commands' do
    job_rows
    entry = fx.record(argv: ['dawarich:jobs:status'], env: { 'DAWARICH_PHOENIX_NODE' => 'dawarich@a' }, after: {}) do
      fx.rake('dawarich:jobs:status', env: { 'DAWARICH_PHOENIX_NODE' => 'dawarich@a' })
    end
    keep('jobs_status_full', entry)
  end

  it 'dawarich:jobs:status for a node that is not beating while Oban owns a key' do
    job_rows
    entry = fx.record(argv: ['dawarich:jobs:status'], env: { 'DAWARICH_PHOENIX_NODE' => 'dawarich@b' }, after: {}) do
      fx.rake('dawarich:jobs:status', env: { 'DAWARICH_PHOENIX_NODE' => 'dawarich@b' })
    end
    keep('jobs_status_stale_alarm', entry)
  end

  it 'points:raw_data:status' do
    fx.user!(2001, 'many@example.invalid')
    fx.user!(2002, 'few@example.invalid')
    fx.month_points!(2001, 20_010, 3)
    fx.month_points!(2001, 20_020, 2, month: 2)
    fx.month_points!(2002, 20_030, 2)
    fx.point!(20_040, 2002, fx::FUTURE)
    fx.archive_user!(2001)
    fx.archive_user!(2002)
    fx.sql('UPDATE points_raw_data_archives SET verified_at = NULL WHERE user_id = 2002')
    fx.sql('UPDATE points_raw_data_archives SET archived_at = ? WHERE user_id = 2002', 30.days.ago)
    fx.sql("UPDATE points SET raw_data = '{}' WHERE id BETWEEN 20010 AND 20012")
    keep('raw_data_status', fx.record(argv: ['points:raw_data:status'], relative:, after: {}) do
      fx.rake('points:raw_data:status')
    end)
  end

  it 'points:raw_data:status on an empty database' do
    keep('raw_data_status_empty', fx.record(argv: ['points:raw_data:status'], after: {}) do
      fx.rake('points:raw_data:status')
    end)
  end

  it 'points:raw_data:verify over every unverified archive, one corrupted' do
    fx.user!(2101, 'verify@example.invalid')
    fx.month_points!(2101, 21_010, 3)
    fx.month_points!(2101, 21_020, 2, month: 2)
    fx.archive_user!(2101)
    fx.sql('UPDATE points_raw_data_archives SET verified_at = NULL')
    fx.corrupt!(fx.archive_id(2101, 2))
    keep('raw_data_verify_all', fx.record(argv: ['points:raw_data:verify'], relative:, after: archives) do
      fx.rake('points:raw_data:verify')
    end)
  end

  it 'points:raw_data:verify for one month leaves verified archives alone' do
    fx.user!(2111, 'month@example.invalid')
    fx.month_points!(2111, 21_110, 2)
    fx.archive_user!(2111)
    fx.month_points!(2111, 21_120, 2)
    fx.month_points!(2111, 21_130, 1, month: 2)
    fx.archive_user!(2111)
    fx.sql('UPDATE points_raw_data_archives SET verified_at = NULL WHERE NOT (month = 1 AND chunk_number = 1)')
    fx.corrupt!(fx.archive_id(2111, 1, 1))
    keep('raw_data_verify_month', fx.record(argv: ['points:raw_data:verify[2111,2020,1]'], relative:,
                                            after: archives) { fx.rake('points:raw_data:verify', '2111', '2020', '1') })
  end

  it 'points:raw_data:clear_verified over every verified archive' do
    fx.user!(2201, 'clear@example.invalid')
    fx.month_points!(2201, 22_010, 3)
    fx.month_points!(2201, 22_020, 2, month: 2)
    fx.archive_user!(2201)
    fx.sql('UPDATE points_raw_data_archives SET verified_at = NULL WHERE month = 2')
    keep('raw_data_clear_all', fx.record(argv: ['points:raw_data:clear_verified'], relative:, after: points) do
      fx.rake('points:raw_data:clear_verified')
    end)
  end

  it 'points:raw_data:clear_verified for one month' do
    fx.user!(2211, 'clear-month@example.invalid')
    fx.month_points!(2211, 22_110, 2)
    fx.month_points!(2211, 22_120, 2, month: 2)
    fx.archive_user!(2211)
    entry = fx.record(argv: ['points:raw_data:clear_verified[2211,2020,2]'], relative:, after: points) do
      fx.rake('points:raw_data:clear_verified', '2211', '2020', '2')
    end
    keep('raw_data_clear_month', entry)
  end

  it 'points:raw_data:archive' do
    fx.user!(2301, 'archive@example.invalid')
    fx.user!(2302, 'gone@example.invalid', deleted: true)
    fx.user!(2303, 'recent@example.invalid')
    fx.month_points!(2301, 23_010, 2)
    fx.month_points!(2301, 23_020, 1, month: 3)
    fx.month_points!(2302, 23_030, 2)
    fx.point!(23_040, 2303, fx::FUTURE)
    keep('raw_data_archive', fx.record(argv: ['points:raw_data:archive'], after: raw) do
      fx.rake('points:raw_data:archive')
    end)
  end

  it 'points:raw_data:archive with nothing to archive' do
    fx.user!(2311, 'idle@example.invalid')
    fx.point!(23_110, 2311, fx::FUTURE)
    keep('raw_data_archive_nothing', fx.record(argv: ['points:raw_data:initial_archive'], after: raw) do
      fx.rake('points:raw_data:initial_archive')
    end)
  end

  it 'points:raw_data:archive_full' do
    fx.user!(2401, 'full@example.invalid')
    fx.month_points!(2401, 24_020, 2, month: 2)
    fx.archive_user!(2401)
    fx.sql('UPDATE points_raw_data_archives SET verified_at = ?', 10.days.ago)
    fx.month_points!(2401, 24_010, 2)
    keep('raw_data_archive_full', fx.record(argv: ['points:raw_data:archive_full'], relative:, after: raw) do
      fx.rake('points:raw_data:archive_full')
    end)
  end

  it 'points:raw_data:archive_full stops when a verification fails' do
    fx.user!(2411, 'stop@example.invalid')
    fx.month_points!(2411, 24_110, 2)
    fx.archive_user!(2411)
    fx.sql('UPDATE points_raw_data_archives SET verified_at = NULL')
    fx.corrupt!(fx.archive_id(2411, 1))
    keep('raw_data_archive_full_failed', fx.record(argv: ['points:raw_data:archive_full'], relative:, after: points,
                                                   stderr: true) { fx.rake('points:raw_data:archive_full') })
  end

  it 'points:raw_data:restore' do
    fx.user!(2501, 'restore@example.invalid')
    fx.month_points!(2501, 25_010, 3)
    fx.archive_user!(2501)
    fx.month_points!(2501, 25_020, 1)
    fx.archive_user!(2501)
    fx.sql("UPDATE points SET raw_data = '{}' WHERE user_id = 2501")
    fx.sql('DELETE FROM points WHERE id = 25011')
    keep('raw_data_restore', fx.record(argv: ['points:raw_data:restore[2501,2020,1]'], relative:, after: points) do
      fx.rake('points:raw_data:restore', '2501', '2020', '1')
    end)
  end

  it 'points:raw_data:restore of an archive line holding a 17-digit float' do
    fx.user!(2531, 'float@example.invalid')
    fx.month_points!(2531, 25_310, 2)
    fx.archive_user!(2531)
    lines = [25_310, 25_311].map { |id| %({"id":#{id},"raw_data":{"acc":0.30000000000000004,"seq":#{id}}}) }
    fx.archive_lines!(fx.archive_id(2531, 1), lines)
    fx.sql("UPDATE points SET raw_data = '{}' WHERE user_id = 2531")
    entry = fx.record(argv: ['points:raw_data:restore[2531,2020,1]'], relative:, after: points) do
      fx.rake('points:raw_data:restore', '2531', '2020', '1')
    end
    keep('raw_data_restore_float', entry)
  end

  it 'points:raw_data:restore without archives' do
    fx.user!(2511, 'none@example.invalid')
    entry = fx.record(argv: ['points:raw_data:restore[2511,2020,1]'], after: {}, stderr: true) do
      fx.rake('points:raw_data:restore', '2511', '2020', '1')
    end
    keep('raw_data_restore_missing', entry)
  end

  it 'points:raw_data:restore with a missing argument' do
    keep('raw_data_restore_usage', fx.record(argv: ['points:raw_data:restore[2511,2020]'], after: {}) do
      fx.rake('points:raw_data:restore', '2511', '2020')
    end)
  end

  it 'points:raw_data:restore_all' do
    fx.user!(2521, 'all@example.invalid')
    fx.month_points!(2521, 25_210, 2)
    fx.month_points!(2521, 25_220, 2, month: 3)
    fx.archive_user!(2521)
    fx.sql("UPDATE points SET raw_data = '{}' WHERE user_id = 2521")
    keep('raw_data_restore_all', fx.record(argv: ['points:raw_data:restore_all[2521]'], relative:, after: points) do
      fx.rake('points:raw_data:restore_all', '2521')
    end)
  end

  it 'points:raw_data:restore_all for an unknown user' do
    keep('raw_data_restore_all_unknown', fx.record(argv: ['points:raw_data:restore_all[999]'], after: {},
                                                   stderr: true) { fx.rake('points:raw_data:restore_all', '999') })
  end

  define_method(:reset_rows) do
    fx.user!(2601, 'reset@example.invalid')
    fx.month_points!(2601, 26_010, 2)
    fx.month_points!(2601, 26_020, 2, month: 2)
    fx.archive_user!(2601)
    fx.sql("UPDATE points SET raw_data = '{}' WHERE id IN (26010, 26011)")
  end

  it 'points:raw_data:reset_all with CONFIRM=true' do
    reset_rows
    entry = fx.record(argv: ['points:raw_data:reset_all'], env: { 'CONFIRM' => 'true' }, relative:, after: raw) do
      fx.rake('points:raw_data:reset_all', env: { 'CONFIRM' => 'true' })
    end
    keep('raw_data_reset_all', entry)
  end

  it 'points:raw_data:reset_all declined at the prompt' do
    reset_rows
    keep('raw_data_reset_all_declined', fx.record(argv: ['points:raw_data:reset_all'], stdin: "n\n", relative:,
                                                  after: raw) { fx.rake('points:raw_data:reset_all', stdin: "n\n") })
  end

  it 'points:raw_data:reset_all with nothing to reset' do
    keep('raw_data_reset_all_nothing', fx.record(argv: ['points:raw_data:reset_all'], after: raw) do
      fx.rake('points:raw_data:reset_all')
    end)
  end

  it 'accepts the password hash Phoenix writes' do
    path = fx::DIR.join('password.json')
    fx.write_password_hash(path) if fx.write?
    fx.user!(1041, 'phoenix-hash@example.invalid')
    hashes = JSON.parse(path.read)
    User.where(id: 1041).update_all(encrypted_password: hashes.fetch('hash'))
    expect(User.find(1041).valid_password?(fx::LOGIN)).to be(true)
    User.where(id: 1041).update_all(encrypted_password: hashes.fetch('long_hash'))
    expect(User.find(1041).valid_password?(fx::LONG)).to be(true)
    expect(User.find(1041).valid_password?(fx::LONG[0, 36] + ('b' * 50))).to be(true)
  end

  context 'A12h ordinary install seeds' do
    self.use_transactional_tests = false

    before do
      fx.reset_seeds!
      @visits_default = fx.conn.select_value('SELECT pg_get_expr(adbin,adrelid) FROM pg_attrdef ' \
                                            'JOIN pg_attribute ON attrelid=adrelid AND attnum=adnum ' \
                                            "WHERE adrelid='users'::regclass AND attname='visits_redetected_at'")
      fx.sql("ALTER TABLE users ALTER visits_redetected_at SET DEFAULT timestamp '#{fx::NOW.strftime('%F %T')}'")
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(BCrypt::Engine).to receive(:generate_salt).and_return(fx::SALT)
      allow(SecureRandom).to receive(:hex).and_call_original
      allow(SecureRandom).to receive(:hex).with(32).and_return('a12e' * 16)
      stub_const('Achievements::LoadRegions::UPSERT_SQL',
                 Achievements::LoadRegions::UPSERT_SQL.gsub(/NOW\(\)/i,
                                                            "timestamp '#{fx::NOW.strftime('%F %T')}'"))
    end

    after do
      fx.reset_seeds!
      fx.sql("ALTER TABLE users ALTER visits_redetected_at SET DEFAULT #{@visits_default}") if @visits_default
    end

    it 'A12h seeds preserves global emptiness guards' do
      fx.user!(1001, 'first@example.invalid')
      fx.user!(1002, 'second@example.invalid')
      fx.user!(1003, 'deleted@example.invalid', deleted: true)
      fx.seed_references!
      Tag.create!(user_id: 1001, name: 'Only', color: '#123456')
      keep('A12h_partial_tables', fx.seed_record)
      expect(Tag.pluck(:user_id, :name)).to eq([[1001, 'Only']])
      fx.user!(1004, 'later@example.invalid')
      keep('A12h_later_user', fx.seed_record)
      expect(Tag.count).to eq(1)
      Tag.delete_all
      keep('A12h_multiple_users', fx.seed_record)
      expect(Tag.group(:user_id).count).to eq(1001 => 4, 1002 => 4, 1004 => 4)
      expect(Country.count).to eq(1)
      expect(Region.count).to eq(1)
    end

    it 'A12h initial admin includes self-hosted create callbacks' do
      keep('A12h_fresh', fx.seed_record)
      user = User.sole
      expect(user).to have_attributes(admin: true, status: 'active', plan: 'pro', points_count: 0,
                                      active_until: 1000.years.from_now)
      expect(user.api_key).to match(/\A[0-9a-f]{64}\z/)
      expect(User.find_by(api_key: user.api_key)).to eq(user)
      expect(user.valid_password?('safepassword')).to be(true)
      expect(user.valid_password?('different-password')).to be(false)
      first = fx.seed_snapshot
      keep('A12h_rerun', fx.seed_record)
      expect(fx.seed_snapshot).to eq(first)
      fx.reset_seeds!
      fx.user!(1003, 'deleted@example.invalid', deleted: true)
      keep('A12h_soft_deleted_only', fx.seed_record)
      expect(User.count).to eq(1)
      expect(User.unscoped.count).to eq(2)
      expect(User.sole.active_until).to eq(1000.years.from_now)
      expect(enqueued_jobs).to be_empty
      expect(fx.conn.select_value('SELECT count(*) FROM job_outbox')).to eq(0)
    end

    it 'A12h seed geometries and failure effects match Rails' do
      keep('A12h_geometries', fx.seed_record)
      expect(fx.conn.select_values('SELECT ST_GeometryType(geom) FROM countries')).to all(eq('ST_MultiPolygon'))
      expect(fx.conn.select_values('SELECT ST_IsValid(geom) FROM regions')).to all(be(true))
      codes = fx.seed_sources.fetch('countries').fetch('features')
                .map { |feature| feature.fetch('properties').fetch('ISO3166-1-Alpha-2') }
      expect(Country.order(:id).pluck(:iso_a2)).to eq(codes)
      fx.reset_seeds!
      invalid = Marshal.load(Marshal.dump(fx.seed_sources))
      invalid['countries']['features'].last['properties']['ISO3166-1-Alpha-3'] = nil
      entry = fx.seed_record(sources: invalid)
      expect(entry.fetch('error').fetch('class')).to eq('ActiveRecord::RecordInvalid')
      expect(Country.count).to eq(0)
      expect(Region.count).to eq(0)
      expect(Tag.count).to eq(0)
      expect(User.count).to eq(1)
      keep('A12h_country_failure', entry)
      allow(Tag).to receive(:create!).and_wrap_original do |original, attributes|
        raise ActiveRecord::RecordInvalid, Tag.new if attributes[:name] == 'Favorite'

        original.call(attributes)
      end
      entry = fx.seed_record
      expect(entry.fetch('error').fetch('class')).to eq('ActiveRecord::RecordInvalid')
      expect(Tag.order(:id).pluck(:name)).to eq(%w[Home Work])
      keep('A12h_partial_tag_failure', entry)
      keep('A12h_partial_tag_rerun', fx.seed_record)
      expect(Tag.count).to eq(2)
    end

    it 'A12h empty countries prevent regions and later seeds' do
      expect { Achievements::LoadRegions.new.call }.to raise_error(Achievements::LoadRegions::MissingCountriesError)
      empty = fx.seed_sources.merge('countries' => { 'type' => 'FeatureCollection', 'features' => [] })
      entry = fx.seed_record(sources: empty)
      expect(entry.fetch('error').fetch('class')).to eq('Achievements::LoadRegions::MissingCountriesError')
      expect(User.sole).to have_attributes(admin: true, active_until: 1000.years.from_now)
      expect(Country.count).to eq(0)
      expect(Region.count).to eq(0)
      expect(Tag.count).to eq(0)
      keep('A12h_empty_countries', entry)
    end

    it 'A12h native on then Rails off recognizes versions without reinserting work' do
      entry = fx.lifecycle_record
      expect(entry['native']['public_versions']).to include('20260314000001')
      expect(entry['native']['jobs'].size).to eq(1)
      expect(entry['native']['jobs'].first).to include('worker' => 'Dawarich.ReleaseOperations.RouteOpacity',
                                                       'args' => { 'version' => 1 }, 'state' => 'scheduled')
      expect(entry['after']).to eq(entry['native'])
      expect(entry['rails_jobs']).to be_empty
      expect(entry['seeds']['error']).to be_nil
      keep('A12h_native_then_rails', entry)
    end
  end
end
