# frozen_string_literal: true

require_relative 'fixture_recording'

module A12d2ReleaseSupport
  COUNTRY_ID = 54_001
  REGION_START = 55_000
  OLD = Time.utc(2026, 1, 1)
  KEYS = %w[command:release.achievements_backfill command:achievements.bulk_check
            command:achievements.check cron:achievements_bulk_check_job].freeze
  PROFILES = %w[countries_empty required_present equal_count_missing cloud self_hosted
                legacy_disabled load_failure enqueue_failure repair_failure repeat].freeze
  VALID = 'MULTIPOLYGON(((0 0,1 0,1 1,0 1,0 0)))'
  INVALID = 'MULTIPOLYGON(((0 0,2 2,2 0,0 2,0 0)))'

  def record_release_fixture(name, corpus)
    FixtureRecording.verify(Rails.root.join("app-phoenix/test/fixtures/a12rel/#{name}.json"),
                            "#{JSON.pretty_generate(corpus)}\n")
  end

  def capture_release_achievements
    corpus = {
      'version' => 1, 'required_codes' => Achievements::Registry.subdivision_codes.to_a.sort,
      'retry' => source_retry(DataMigrations::BackfillAchievementsJob),
      'cases' => PROFILES.map { |profile| release_isolated { release_achievement_case(profile) } }
    }
    geometries = []
    encode = lambda do |value|
      case value
      when Array then value.map { encode.call(_1) }
      when Hash
        value.to_h do |key, child|
          if key == 'ewkb'
            index = geometries.index(child)
            index ||= geometries.push(child).size - 1
            ['geometry', index]
          else
            [key, encode.call(child)]
          end
        end
      else value
      end
    end
    encode.call(corpus).merge('geometries' => geometries)
  end

  def capture_release_achievement_vectors
    migrations = {
      '20260922120000' => %w[enqueue_achievements_backfill EnqueueAchievementsBackfill],
      '20260923180000' => %w[enqueue_ungated_achievements_backfill EnqueueUngatedAchievementsBackfill]
    }
    vectors = migrations.map do |version, (file, name)|
      require Rails.root.join("db/migrate/#{version}_#{file}")
      release_isolated do
        name.constantize.new.up
        { 'version' => version, 'jobs' => source_jobs }
      end
    end
    { 'version' => 1, 'vectors' => vectors }
  end

  def release_isolated(&block)
    connection = ActiveRecord::Base.connection
    expect(connection.open_transactions).to eq(0)
    expect(Country.count).to eq(0)
    expect(Region.count).to eq(0)
    phoenix_tables!
    sequences = %w[countries regions flipper_features flipper_gates].index_with do |table|
      connection.select_one("SELECT last_value, is_called FROM #{table}_id_seq")
    end
    owners = connection.select_all("SELECT * FROM phoenix.job_owners WHERE key IN (#{release_keys})").to_a
    unrelated_query = "SELECT * FROM phoenix.job_owners WHERE key NOT IN (#{release_keys}) ORDER BY key"
    unrelated_owners = connection.select_all(unrelated_query).to_a
    flag = connection.select_all("SELECT * FROM flipper_features WHERE key = 'achievements'").to_a
    gates = connection.select_all("SELECT * FROM flipper_gates WHERE feature_key = 'achievements'").to_a
    RSpec::Mocks.with_temporary_scope do
      allow(SecureRandom).to receive(:uuid).and_return(A12d2JobsSupport::UUID)
      KEYS.each { JobOwnership.put!(_1, :sidekiq, pinned: true, by: 'a12rel-source') }
      connection.execute("SELECT setval('regions_id_seq', #{REGION_START}, false)")
      clear_enqueued_jobs
      travel_to(A12d2JobsSupport::NOW) do
        Time.use_zone('Europe/Berlin', &block)
      end
    end
  ensure
    if sequences
      connection.execute("DELETE FROM regions WHERE id >= #{REGION_START}")
      Country.where(id: COUNTRY_ID, name: 'A12rel synthetic country').delete_all
      connection.execute("DELETE FROM phoenix.job_owners WHERE key IN (#{release_keys})")
      release_restore_rows('phoenix.job_owners', owners)
      expect(connection.select_all(unrelated_query).to_a).to eq(unrelated_owners)
      connection.execute("DELETE FROM flipper_gates WHERE feature_key = 'achievements'")
      connection.execute("DELETE FROM flipper_features WHERE key = 'achievements'")
      release_restore_rows('flipper_features', flag)
      release_restore_rows('flipper_gates', gates)
      sequences.each do |table, state|
        connection.execute("SELECT setval('#{table}_id_seq', #{state.fetch('last_value')}, " \
                           "#{connection.quote(state.fetch('is_called'))})")
      end
    end
    clear_enqueued_jobs
    PhoenixSchema.reset!
  end

  def release_keys
    KEYS.map { ActiveRecord::Base.connection.quote(_1) }.join(', ')
  end

  def release_restore_rows(table, rows)
    connection = ActiveRecord::Base.connection
    rows.each do |row|
      columns = row.keys.map { connection.quote_column_name(_1) }.join(', ')
      values = row.values.map { connection.quote(_1) }.join(', ')
      connection.execute("INSERT INTO #{table} (#{columns}) VALUES (#{values})")
    end
  end

  def release_achievement_case(profile)
    connection = ActiveRecord::Base.connection
    codes = Achievements::Registry.subdivision_codes.to_a.sort
    unless profile == 'countries_empty'
      create(:country, id: COUNTRY_ID, name: 'A12rel synthetic country', created_at: OLD, updated_at: OLD)
    end
    seed_codes = case profile
                 when 'required_present'
                   codes
                 when 'equal_count_missing'
                   %w[DE-BE ZZ-INVALID ZZ-SENTINEL] + (1..(codes.size - 3)).map { "ZZ-#{_1}" }
                 when 'countries_empty'
                   ['ZZ-SENTINEL']
                 else
                   %w[DE-BE ZZ-INVALID ZZ-SENTINEL]
                 end
    release_seed_regions(seed_codes)
    before = release_regions
    allow(DawarichSettings).to receive(:self_hosted?).and_return(%w[self_hosted legacy_disabled].include?(profile))
    Flipper.disable(:achievements) if profile == 'legacy_disabled'
    expect(Flipper.enabled?(:achievements)).to be(false) if profile == 'legacy_disabled'
    statements = []
    release_trace_loader(connection, profile, statements)
    if profile == 'enqueue_failure'
      allow(Achievements::BulkCheckJob).to receive(:perform_later).and_raise('A12rel enqueue failure')
    end
    error = release_perform_parent
    release_perform_parent if profile == 'repeat'
    after = release_regions(statements:)
    result = { 'id' => profile, 'before' => before, 'after' => after, 'statements' => statements,
               'error' => error, 'jobs' => source_jobs }
    before.each do |row|
      actual = after.find { _1.fetch('code') == row.fetch('code') }
      expect(actual.slice('id', 'code', 'created_at')).to eq(row.slice('id', 'code', 'created_at'))
    end
    expect(after.find { _1.fetch('code') == 'ZZ-SENTINEL' }).to eq(before.find { _1.fetch('code') == 'ZZ-SENTINEL' })
    if %w[enqueue_failure repair_failure].include?(profile)
      result['observed'] = release_second_connection_regions(statements)
      allow(Achievements::BulkCheckJob).to receive(:perform_later).and_call_original
      retry_statements = []
      release_trace_loader(connection, 'retry', retry_statements)
      clear_enqueued_jobs
      result['retry'] = { 'error' => release_perform_parent, 'jobs' => source_jobs,
                          'statements' => retry_statements, 'after' => release_regions(statements:) }
      expect(result.fetch('retry').fetch('after')).to eq(after)
    end
    result
  end

  def release_seed_regions(codes)
    rows = codes.each_with_index.map do |code, index|
      { id: REGION_START + index, code:, geom: code == 'ZZ-INVALID' ? INVALID : VALID,
        created_at: OLD, updated_at: OLD }
    end
    Region.insert_all!(rows)
    ActiveRecord::Base.connection.execute("SELECT setval('regions_id_seq', #{REGION_START + codes.size}, false)")
  end

  def release_trace_loader(connection, profile, statements)
    allow(connection).to receive(:execute).and_wrap_original do |original, sql, *args, **kwargs|
      kind = if sql.start_with?('INSERT INTO regions (code, geom, created_at, updated_at)')
               'upsert'
             elsif sql.start_with?("UPDATE regions\nSET geom")
               'repair'
             end
      next original.call(sql, *args, **kwargs) unless kind

      lower = connection.select_value('SELECT clock_timestamp()')
      error = nil
      begin
        if (profile == 'load_failure' && kind == 'upsert') || (profile == 'repair_failure' && kind == 'repair')
          original.call("#{sql}\nRETURNING a12rel_missing_column", *args, **kwargs)
        else
          original.call(sql, *args, **kwargs)
        end
      rescue ActiveRecord::StatementInvalid => e
        error = e
      end
      upper = connection.select_value('SELECT clock_timestamp()')
      snapshot = release_regions_raw(connection)
      if kind == 'upsert' && !error
        expected = JSON.parse(File.read(Rails.root.join(Achievements::LoadRegions::ASSET_PATH)))
                       .fetch('features').map { _1.fetch('properties').fetch('iso_3166_2') }
        snapshot.select { expected.include?(_1.fetch('code')) }.each do |row|
          expect(row.fetch('updated_at')).to be_between(lower, upper)
          if row.fetch('created_at') == OLD
            expect(row.fetch('updated_at')).to be > OLD
          else
            expect(row.fetch('created_at')).to eq(row.fetch('updated_at'))
          end
        end
      elsif kind == 'repair'
        expect(snapshot.map { _1.slice('id', 'code', 'created_at', 'updated_at') })
          .to eq(@release_after_upsert.map { _1.slice('id', 'code', 'created_at', 'updated_at') })
      end
      @release_after_upsert = snapshot if kind == 'upsert' && !error
      statements << { 'kind' => kind, 'committed' => error.nil?,
                      'timestamp_predicates' => kind == 'upsert' && !error ? 'bounded_database_now' : 'preserved' }
      if kind == 'upsert' && !error
        @release_generated_at = snapshot.first do
          _1.fetch('updated_at') != OLD
        end&.fetch('updated_at')
      end
      raise error if error
    end
  end

  def release_perform_parent
    DataMigrations::BackfillAchievementsJob.new.perform
    nil
  rescue StandardError => e
    { 'class' => e.class.name, 'message' => e.message.lines.first.strip }
  end

  def release_regions_raw(connection)
    connection.select_all("SELECT id, code, encode(ST_AsEWKB(geom), 'hex') AS ewkb, " \
                          'ST_IsValid(geom) AS valid, created_at, updated_at FROM regions ORDER BY id').to_a
  end

  def release_regions(statements: [])
    release_project_regions(release_regions_raw(ActiveRecord::Base.connection), statements)
  end

  def release_project_regions(rows, statements)
    rows.map do |row|
      row.transform_values.with_index do |value, index|
        field = row.keys[index]
        if %w[created_at updated_at].include?(field) && value != OLD
          expect(statements).to include(include('kind' => 'upsert', 'committed' => true))
          expect(value).to eq(@release_generated_at)
          { 'database_now' => 'upsert', 'bounded' => true }
        else
          source_value(value)
        end
      end
    end
  end

  def release_second_connection_regions(statements)
    original = ActiveRecord::Base.connection.raw_connection.object_id
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        expect(connection.raw_connection.object_id).not_to eq(original)
        expect(connection.open_transactions).to eq(0)
        release_project_regions(release_regions_raw(connection), statements)
      end
    end.value
  end
end
