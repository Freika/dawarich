# frozen_string_literal: true

require 'open3'
require 'stringio'

module A12eFixtureSupport
  DIR = Rails.root.join('app-phoenix/test/fixtures/a12e')
  PHRASE = 'phoenix-a12e-archive-phrase-not-for-production'
  LOGIN = 'phoenix-a12e-login-not-for-production'
  SALT = '$2a$12$PhoenixA12eCorpusSaltu'
  LONG = ('ä' * 128).freeze
  RESET = 'phoenix-a12e-pending-reset'
  STAMP = '2026-01-01 00:00:00'
  NOW = Time.utc(2026, 10, 1, 12)
  FUTURE = 2_000_000_000
  RAW = { 'tid' => 'a1', 'acc' => 0.30000000000000004, 'batt' => 87 }.freeze
  TABLES = %w[users points_raw_data_archives points active_storage_blobs active_storage_attachments job_outbox
              phoenix.job_owners phoenix.runtime_nodes phoenix.rails_commands phoenix.rails_commands_dead].freeze
  SEQUENCES = %w[users points_raw_data_archives points active_storage_blobs active_storage_attachments
                 phoenix.rails_commands].freeze
  ORDER = { 'phoenix.job_owners' => 'key DESC', 'phoenix.runtime_nodes' => 'node', 'job_outbox' => 'event_id' }.freeze
  SIZES = [0, 1, 2, 1023, 1024, 1025, 1536, 10_240, 1_048_575, 1_048_576, 1_234_567, 1_073_741_824,
           5_368_709_120, 1_099_511_627_776, 1_125_899_906_842_624].freeze

  module_function

  def write? = ENV['WRITE_PHOENIX_FIXTURES'] == '1'
  def conn = ActiveRecord::Base.connection
  def sql(text, *binds) = conn.execute(ActiveRecord::Base.sanitize_sql_array([text, *binds]))

  def stored
    @stored ||= DIR.join('cli.json').exist? ? JSON.parse(DIR.join('cli.json').read) : { 'cases' => [] }
  end

  def reset!
    conn.execute('TRUNCATE users, points, points_raw_data_archives, active_storage_attachments, ' \
                 'active_storage_blobs, job_outbox RESTART IDENTITY CASCADE')
    %w[job_owners runtime_nodes rails_commands rails_commands_dead].each do |table|
      conn.execute("DELETE FROM phoenix.#{table}")
    end
    FileUtils.rm_rf(Dir[Rails.root.join('tmp/storage/*').to_s])
  end

  def user!(id, email, status: 1, deleted: false, admin: false, reset: false)
    values = [id, email, status, admin, deleted ? STAMP : nil, STAMP, STAMP, STAMP, reset ? "#{RESET}-#{id}" : nil,
              reset ? STAMP : nil]
    sql(<<~SQL.squish, *values)
      INSERT INTO users (id, email, encrypted_password, api_key, status, admin, deleted_at, created_at, updated_at,
                         visits_redetected_at, reset_password_token, reset_password_sent_at)
      VALUES (?, ?, '', '', ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def point!(id, user_id, timestamp, raw = RAW)
    sql(<<~SQL.squish, id, user_id, timestamp, Oj.dump(raw, mode: :strict, float_precision: 0), STAMP, STAMP)
      INSERT INTO points (id, user_id, timestamp, raw_data, lonlat, created_at, updated_at)
      VALUES (?, ?, ?, ?::jsonb, ST_SetSRID(ST_MakePoint(12.3731, 51.3397), 4326)::geography, ?, ?)
    SQL
  end

  def month_points!(user_id, first_id, count, year: 2020, month: 1)
    base = Time.utc(year, month, 1).to_i + (first_id % 1000)
    count.times { |i| point!(first_id + i, user_id, base + (3600 * i), RAW.merge('seq' => first_id + i)) }
  end

  def archive_user!(user_id)
    with_env('ARCHIVE_ENCRYPTION_KEY' => PHRASE) { Points::RawData::Archiver.new.archive_user(user_id) }
  end

  def archive_id(user_id, month, chunk = 1)
    conn.select_value(ActiveRecord::Base.sanitize_sql_array(
                        ['SELECT id FROM points_raw_data_archives WHERE user_id = ? AND month = ? AND chunk_number = ?',
                         user_id, month, chunk]
                      ))
  end

  def corrupt!(archive_id)
    blob = Points::RawDataArchive.find(archive_id).file.blob
    blob.service.upload(blob.key, StringIO.new('corrupted archive bytes'))
  end

  def with_env(vars)
    saved = vars.keys.index_with { |key| ENV.fetch(key, nil) }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    Points::RawData::Encryption.reset!
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    Points::RawData::Encryption.reset!
  end

  def rake(task, *args, stdin: nil, env: {})
    out = StringIO.new
    err = StringIO.new
    code = capture(out, err, stdin) do
      with_env(env.merge('ARCHIVE_ENCRYPTION_KEY' => PHRASE)) do
        reenable(Rake::Task[task])
        Rake::Task[task].invoke(*args)
      end
    end
    [out.string, err.string, code]
  end

  def reenable(task)
    task.reenable
    task.prerequisite_tasks.reject { |prerequisite| prerequisite.name == 'environment' }.each { |p| reenable(p) }
  end

  def capture(out, err, stdin)
    saved = [$stdout, $stderr, $stdin]
    $stdout = out
    $stderr = err
    $stdin = StringIO.new(stdin.to_s)
    yield
    0
  rescue SystemExit => e
    e.status
  rescue StandardError => e
    err.puts(e.message)
    1
  ensure
    $stdout, $stderr, $stdin = saved
  end

  def recipe
    yield
    ['', '', 0]
  end

  def record(argv:, after:, env: {}, stdin: nil, drop: [], relative: {}, stdout: true, stderr: false)
    seed = snapshot(relative)
    drop.each { |table| conn.execute("DROP TABLE #{table} CASCADE") }
    out, err, code = yield
    { 'argv' => argv, 'env' => env, 'stdin' => stdin, 'drop' => drop, 'seed' => seed,
      'stdout' => stdout ? out : nil, 'stderr' => stderr ? err : nil, 'exit' => code,
      'after' => after.transform_values { |query| { 'sql' => query, 'json' => pg_json(query) } } }
  end

  def pg_json(query)
    conn.select_value("SELECT coalesce(json_agg(row_to_json(q)), '[]')::text FROM (#{query}) q")
  end

  def snapshot(relative)
    now = Time.current
    tables = TABLES.filter_map do |table|
      rows = JSON.parse(conn.select_value(
                          "SELECT coalesce(json_agg(row_to_json(t) ORDER BY t.#{ORDER.fetch(table, 'id')}), '[]') " \
                          "FROM #{table} t"
                        ))
      next if rows.empty?

      Array(relative[table]).each do |column|
        rows.each do |row|
          row[column] = { 'ago' => (now - Time.find_zone('UTC').parse(row[column])).round } if row[column]
        end
      end
      [table, rows]
    end
    objects = ActiveStorage::Blob.order(:key).to_h { |blob| [blob.key, Base64.strict_encode64(blob.download)] }
    { 'tables' => tables, 'sequences' => SEQUENCES, 'objects' => objects }
  end

  def normalized(data) = JSON.parse(Oj.dump(data, mode: :strict, float_precision: 0))
  def comparable(entry) = normalized(entry).except('seed')
  def human_sizes = SIZES.map { |n| [n, ActiveSupport::NumberHelper.number_to_human_size(n)] }

  def write_password_hash(path)
    long = "String.duplicate(<<195, 164>>, #{LONG.length})"
    code = "h = &Dawarich.CLI.Users.hash_password(&1, #{SALT.inspect}); " \
           "IO.puts(Jason.encode!([h.(#{LOGIN.inspect}), h.(#{long})]))"
    out, status = Open3.capture2e(phoenix_env, 'mix', 'run', '--no-start', '-e', code,
                                  chdir: Rails.root.join('app-phoenix').to_s)
    raise out unless status.success?

    hash, long_hash = JSON.parse(out.lines.last)
    data = { 'hash' => hash, 'long_hash' => long_hash, 'salt' => SALT }
    path.write("#{Oj.dump(data, mode: :strict, indent: 2)}\n")
  end

  def archive_lines!(archive_id, lines)
    io = StringIO.new
    gzip = Zlib::GzipWriter.new(io)
    lines.each { |line| gzip.write("#{line}\n") }
    gzip.close
    data = with_env('ARCHIVE_ENCRYPTION_KEY' => PHRASE) { Points::RawData::Encryption.encrypt(io.string) }
    blob = Points::RawDataArchive.find(archive_id).file.blob
    blob.service.upload(blob.key, StringIO.new(data))
  end

  def phoenix_env
    { 'MIX_ENV' => 'test', 'PATH' => "#{Dir.home}/.asdf/shims:#{ENV.fetch('PATH')}",
      'ASDF_ERLANG_VERSION' => '27.3.4.1', 'ASDF_ELIXIR_VERSION' => '1.18.3-otp-27',
      'PHOENIX_TEST_REDIS_URL' => 'redis://127.0.0.1:7196/1', 'DATABASE_HOST' => '127.0.0.1' }
  end

  def finish(recorded)
    return unless write? && recorded.any?

    FileUtils.mkdir_p(DIR)
    data = { 'cases' => recorded.sort.map { |name, entry| entry.merge('name' => name) },
             'human_sizes' => human_sizes }
    DIR.join('cli.json').write("#{Oj.dump(data, mode: :strict, indent: 2, float_precision: 0)}\n")
  end
end
