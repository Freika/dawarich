# frozen_string_literal: true

require_relative 'a12d2_jobs_support'
require_relative 'fixture_recording'

module NormalImportReleaseSupport
  include A12d2JobsSupport

  RELEASE_DIR = Rails.root.join('app-phoenix/test/fixtures/a12rel')
  STAMP = Time.utc(2026, 1, 15, 23, 30)
  BASE = STAMP.to_i
  OWNER_IDS = [987_001, 987_002, 987_003].freeze
  IMPORT_IDS = (987_101..987_107).to_a.freeze
  TRACK_IDS = [56_201, 56_202, 56_203, 56_204].freeze
  TABLES = %w[users imports points tracks track_segments active_storage_blobs active_storage_attachments].freeze
  RELEASE_KEYS = %w[command:release.import_backfill command:release.transportation
                    command:tracks.reclassify command:tracks.reclassify_user].freeze
  IMPORT_CASES = %w[semantic phone_object phone_array google_records owntracks geojson missing deleted
                    unsupported nil_source deleting absent download_error malformed shape_error sql_failure
                    phone_sql_failure repeat checksum size empty].freeze
  BATCH_CASES = %w[selection preservation empty fallback sql_failure unchanged nil_user deleted_user].freeze

  def record_import_release_fixture(name, corpus)
    FixtureRecording.verify(RELEASE_DIR.join("#{name}.json"), "#{JSON.pretty_generate(corpus)}\n")
  end

  def import_release_isolated(&block)
    connection = ActiveRecord::Base.connection
    expect(connection.open_transactions).to eq(0)
    expect(User.unscoped.where(id: OWNER_IDS)).not_to exist
    phoenix_tables!
    sequences = TABLES.index_with { connection.select_one("SELECT last_value, is_called FROM #{_1}_id_seq") }
    keys = RELEASE_KEYS.map { connection.quote(_1) }.join(', ')
    owners = connection.select_all("SELECT * FROM phoenix.job_owners WHERE key IN (#{keys})").to_a
    @release_blobs = []
    RSpec::Mocks.with_temporary_scope do
      allow(SecureRandom).to receive(:uuid).and_return(A12d2JobsSupport::UUID)
      RELEASE_KEYS.each { JobOwnership.put!(_1, :sidekiq, pinned: true, by: 'a12rel-source') }
      TABLES.each { connection.execute("SELECT setval('#{_1}_id_seq', 56500, false)") }
      clear_enqueued_jobs
      travel_to(STAMP) { Time.use_zone('Europe/Berlin', &block) }
    end
  ensure
    if sequences
      @release_blobs.each { |blob| blob.service.delete(blob.key) }
      ActiveStorage::Attachment.where(record_type: 'Import', record_id: IMPORT_IDS).delete_all
      ActiveStorage::Blob.where(id: @release_blobs.map(&:id)).delete_all
      Point.where(user_id: OWNER_IDS).delete_all
      TrackSegment.where(track_id: TRACK_IDS).delete_all
      Track.where(id: TRACK_IDS).delete_all
      Notification.where(user_id: OWNER_IDS).delete_all
      Import.where(user_id: OWNER_IDS).delete_all
      User.unscoped.where(id: OWNER_IDS).delete_all
      connection.execute("DELETE FROM phoenix.job_owners WHERE key IN (#{keys})")
      owners.each do |row|
        columns = row.keys.map { connection.quote_column_name(_1) }.join(', ')
        values = row.values.map { connection.quote(_1) }.join(', ')
        connection.execute("INSERT INTO phoenix.job_owners (#{columns}) VALUES (#{values})")
      end
      sequences.each do |table, state|
        connection.execute("SELECT setval('#{table}_id_seq', #{state.fetch('last_value')}, " \
                           "#{connection.quote(state.fetch('is_called'))})")
      end
    end
    clear_enqueued_jobs
    PhoenixSchema.reset!
  end

  def capture_release_imports
    cases = IMPORT_CASES.map { |profile| import_release_isolated { capture_release_import_case(profile) } }
    { 'version' => 1, 'ambient_zone' => 'Europe/Berlin', 'now' => STAMP.iso8601(6),
      'retry' => source_retry(TransportationModes::ImportBackfillJob), 'cases' => cases }
  end

  def capture_release_import_case(profile)
    user, import = NormalImportFormatsSupport.owner!('Asia/Tokyo', 'de')
    source = if profile.start_with?('phone')
               'google_phone_takeout'
             elsif %w[google_records owntracks geojson].include?(profile)
               profile
             else
               'google_semantic_history'
             end
    source = 'csv' if profile == 'unsupported'
    source = nil if profile == 'nil_source'
    import.update_columns(source:, status: profile == 'deleting' ? :deleting : :completed,
                          raw_points: 17, doubles: 3, processed: 9, raw_data: { 'retained' => 'import' })
    import.skip_background_processing = true
    release_import_sentinel(user)
    offsets = [-120, -60, 0, 0, 60, 120]
    offsets.each_with_index { |offset, index| release_point(56_301 + index, import.id, offset) }
    Point.where(id: 56_302).update_all(motion_data: {})
    bytes = release_import_bytes(profile)
    input = "inputs/#{profile}.json"
    FixtureRecording.verify(RELEASE_DIR.join(input), bytes) unless %w[missing deleted absent].include?(profile)
    release_attach(import, profile, bytes) unless %w[missing deleted absent].include?(profile)
    Point.where(import_id: import.id).delete_all if profile == 'deleted'
    import.delete if profile == 'deleted'
    track_calls = []
    downloads = 0
    allow(Tracks::Reprocessor).to receive(:new).and_wrap_original do |original, **options|
      instance = original.call(**options)
      allow(instance).to receive(:reprocess_for_import).and_wrap_original do |work|
        track_calls << options.fetch(:import).id
        work.call
      end
      instance
    end
    service = ActiveStorage::Service::DiskService
    allow_any_instance_of(service).to receive(:download).and_wrap_original do |original, *args|
      downloads += 1
      original.call(*args)
    end
    before = release_import_snapshot
    connection = ActiveRecord::Base.connection
    updates = []
    if profile == 'sql_failure' || profile.start_with?('phone')
      count = 0
      allow(connection).to receive(:exec_update).and_wrap_original do |original, sql, *args, **kwargs|
        if sql.start_with?('UPDATE "points"')
          count += 1
          updates << args.last.last.value_for_database if profile.start_with?('phone')
          failure_at = profile == 'phone_sql_failure' ? 1 : 2
          if %w[sql_failure phone_sql_failure].include?(profile) && count == failure_at
            next connection.execute('UPDATE points SET a12rel_missing_column = 1')
          end
        end
        original.call(sql, *args, **kwargs)
      end
    end
    id = profile == 'missing' ? 0 : import.id
    error = release_import_error { TransportationModes::ImportBackfillJob.new.perform(id) }
    release_import_error { TransportationModes::ImportBackfillJob.new.perform(id) } if profile == 'repeat'
    after = release_import_snapshot
    expect(after.fetch('imports')).to eq(before.fetch('imports'))
    expect(after.fetch('points').map { _1.except('motion_data') })
      .to eq(before.fetch('points').map { _1.except('motion_data') })
    expect(after.fetch('points').select { _1.fetch('import_id') == 987_102 })
      .to eq(before.fetch('points').select { _1.fetch('import_id') == 987_102 })
    input = nil if %w[missing deleted absent].include?(profile)
    result = { 'id' => profile, 'source' => source, 'input' => input, 'before' => before, 'after' => after,
               'error' => error, 'downloads' => downloads, 'track_calls' => track_calls.dup, 'jobs' => source_jobs }
    result['update_order'] = updates.dup if profile.start_with?('phone')
    if %w[sql_failure phone_sql_failure].include?(profile)
      result['observed'] = release_import_observed { |second| release_import_snapshot(second) }
      allow(connection).to receive(:exec_update).and_call_original
      result['retry'] = { 'error' => release_import_error { TransportationModes::ImportBackfillJob.new.perform(id) },
                          'after' => release_import_snapshot, 'track_calls' => track_calls.dup }
    end
    result
  end

  def release_import_sentinel(user)
    Import.insert_all!([{ id: 987_102, user_id: user.id, name: 'A12rel sentinel', source: 6,
                         created_at: STAMP, updated_at: STAMP }])
    release_point(56_399, 987_102, 0)
  end

  def release_point(id, import_id, offset, track_id: nil)
    Point.insert_all!([{ id:, user_id: 987_001, import_id:, track_id:, timestamp: BASE + offset,
                        lonlat: "POINT(#{12.4 + (id - 56_300) * 0.00001} 51.3)", velocity: '3.25',
                        motion_data: { 'retained' => 'point', 'activityRecord' => { 'old' => true } },
                        raw_data: { 'retained' => 'raw' }, created_at: STAMP - 86_400, updated_at: STAMP - 86_400 }])
  end

  def release_import_bytes(profile)
    return '' if profile == 'empty'
    return '{"timelineObjects":[' if profile == 'malformed'

    if profile.start_with?('phone')
      signals = [[30, 'tie_before'], [-180, 'window_60'], [181, 'outside_61'], [1, 'near'],
                 [-1, 'equal_later'], [0, 'exact_first'], [0, 'exact_later']].map do |offset, label|
        { 'activityRecord' => { 'timestamp' => Time.at(BASE + offset).utc.iso8601,
                                'probableActivities' => [{ 'type' => 'CYCLING', 'confidence' => 0.9 }],
                                'extra' => label, 'nullable' => nil } }
      end
      signals += [nil, {}, { 'activityRecord' => nil }, { 'activityRecord' => { 'timestamp' => nil } }]
      return (profile == 'phone_array' ? signals : { 'rawSignals' => signals }).to_json
    end
    segments = [
      { 'activities' => [{ 'activityType' => 'WALKING', 'probability' => 0.7 }], 'activityType' => 'WALKING',
        'duration' => { 'startTimestamp' => Time.at(BASE - 60).utc.iso8601,
                        'endTimestamp' => Time.at(BASE + 60).utc.iso8601 } },
      { 'activityType' => 'CYCLING', 'waypointPath' => { 'travelMode' => 'CYCLING' },
        'duration' => { 'startTimestamp' => BASE.to_s, 'endTimestamp' => ((BASE + 120) * 1000).to_s } }
    ]
    segments.last['duration'] = 'invalid shape' if profile == 'shape_error'
    { 'timelineObjects' => [nil, false, { 'activitySegment' => false }, { 'activitySegment' => [] }] +
      segments.map { { 'activitySegment' => _1 } } }.to_json
  end

  def release_attach(import, profile, bytes)
    blob = ActiveStorage::Blob.create!(id: 56_501, key: "a12rel-#{profile}", filename: 'synthetic.json',
                                       content_type: 'application/json', byte_size: bytes.bytesize,
                                       checksum: Digest::MD5.base64digest(bytes), service_name: 'test',
                                       created_at: STAMP)
    @release_blobs << blob
    blob.upload_without_unfurling(StringIO.new(bytes))
    ActiveStorage::Attachment.insert_all!([{ id: 56_601, name: 'file', record_type: 'Import', record_id: import.id,
                                            blob_id: blob.id, created_at: STAMP }])
    blob.service.delete(blob.key) if profile == 'download_error'
    blob.update_columns(checksum: Digest::MD5.base64digest('other bytes')) if profile == 'checksum'
    blob.update_columns(byte_size: bytes.bytesize + 1) if profile == 'size'
  end

  def release_import_error
    yield
    nil
  rescue StandardError => e
    { 'class' => e.class.name, 'message' => e.message.lines.first.strip }
  end

  def release_import_snapshot(connection = ActiveRecord::Base.connection)
    point_fields = Point.column_names - ['lonlat']
    geometry = "encode(ST_AsEWKB(lonlat::geometry), 'hex') AS ewkb"
    points = connection.select_all("SELECT #{point_fields.join(', ')}, #{geometry} " \
                                   "FROM points WHERE user_id IN (#{OWNER_IDS.join(',')}) ORDER BY id").to_a
    points.each do |row|
      %w[motion_data raw_data].each { |key| row[key] = JSON.parse(row[key]) if row[key].is_a?(String) }
    end
    fields = Import.column_names
    imports = connection.select_all("SELECT #{fields.join(', ')} FROM imports " \
                                    "WHERE user_id IN (#{OWNER_IDS.join(',')}) ORDER BY id").to_a
    imports.each do |row|
      %w[raw_data additional_data_extraction].each do |key|
        row[key] = JSON.parse(row[key]) if row[key].is_a?(String)
      end
    end
    source_value('points' => points, 'imports' => imports)
  end

  def release_import_observed
    original = ActiveRecord::Base.connection.raw_connection.object_id
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |second|
        expect(second.raw_connection.object_id).not_to eq(original)
        expect(second.open_transactions).to eq(0)
        yield second
      end
    end.value
  end

  def capture_release_track_batches
    { 'version' => 1, 'ambient_zone' => 'Europe/Berlin', 'now' => STAMP.iso8601(6),
      'cases' => BATCH_CASES.map { |profile| import_release_isolated { release_track_case(profile) } } }
  end

  def release_track_case(profile)
    user, import = NormalImportFormatsSupport.owner!('Asia/Tokyo', 'de')
    user.update_columns(settings: { 'enabled_transportation_modes' => %w[walking cycling], 'timezone' => 'Asia/Tokyo' })
    release_import_sentinel(user)
    TRACK_IDS.each_with_index do |id, index|
      release_track(id, index, profile == 'unchanged' ? :unknown : :driving)
      next if index == 3

      release_point(56_301 + index * 10, import.id, index * 3600, track_id: id)
      release_point(56_302 + index * 10, import.id, index * 3600 + 600, track_id: id)
      release_segment(56_401 + index, id, index * 3600, :driving)
    end
    Point.where(id: 56_399).update_all(track_id: TRACK_IDS.first)
    release_point(56_398, import.id, 9999)
    if profile == 'preservation'
      release_segment(56_411, TRACK_IDS.first, 100, :cycling, corrected_at: STAMP - 86_400)
      release_segment(56_412, TRACK_IDS.first, 300, :boat,
                      source: EnhancedImport::Translator::SEGMENT_SOURCE_LABELS.first)
    end
    user.update_columns(deleted_at: STAMP) if %w[nil_user deleted_user].include?(profile)
    detectors = []
    reports = []
    broadcasts = []
    tile_ranges = []
    allow(ExceptionReporter).to receive(:call) do |error, message|
      reports << { 'class' => error.class.name, 'message' => error.message.lines.first.strip, 'context' => message }
    end
    allow(TracksChannel).to receive(:broadcast_to) do |recipient, payload|
      broadcasts << source_value('user_id' => recipient&.id, 'payload' => payload)
    end
    allow(Tracks::TileEpoch).to receive(:bump_range) { |*args| tile_ranges << args }
    allow(TransportationModes::Detector).to receive(:new).and_wrap_original do |original, track, **options|
      detectors << source_value('track_id' => track.id, 'enabled_modes' => options[:enabled_modes],
                                'preserved' => options.fetch(:preserved).map(&:id),
                                'fallback' => options.fetch(:fallback))
      instance = original.call(track, **options)
      allow(instance).to receive(:call).and_return([]) if profile == 'empty'
      instance
    end
    if %w[fallback sql_failure unchanged].include?(profile)
      allow(TransportationModes::FeatureExtractor).to receive(:call).and_raise('A12rel feature failure')
    end
    connection = ActiveRecord::Base.connection
    if profile == 'sql_failure'
      allow(connection).to receive(:exec_insert_all).and_wrap_original do |original, sql, *args, **kwargs|
        if sql.start_with?('INSERT INTO "track_segments"') && sql.include?('56202')
          next connection.execute('UPDATE track_segments SET a12rel_missing_column = 1')
        end

        original.call(sql, *args, **kwargs)
      end
    end
    before = release_track_snapshot
    attempted = Tracks::Reprocessor.new(import:).reprocess_for_import
    after = release_track_snapshot
    result = { 'id' => profile, 'before' => before, 'after' => after, 'attempted' => attempted,
               'detectors' => detectors.dup, 'reported' => reports.dup, 'broadcasts' => broadcasts.dup,
               'tile_ranges' => tile_ranges.dup, 'points' => release_import_snapshot.fetch('points') }
    expect(after.fetch('tracks').find { _1.fetch('id') == TRACK_IDS.last })
      .to eq(before.fetch('tracks').find { _1.fetch('id') == TRACK_IDS.last })
    if profile == 'sql_failure'
      result['observed'] = release_import_observed { |second| release_track_snapshot(second) }
      allow(connection).to receive(:exec_insert_all).and_call_original
      result['retry'] = { 'attempted' => Tracks::Reprocessor.new(import:).reprocess_for_import,
                          'after' => release_track_snapshot }
    end
    result
  end

  def release_track(id, index, mode)
    Track.insert_all!([{ id:, user_id: 987_001, tracker_id: "a12rel-#{index}",
                        start_at: Time.at(BASE + index * 3600).utc, end_at: Time.at(BASE + index * 3600 + 600).utc,
                        original_path: 'LINESTRING(12.4 51.3,12.41 51.31)', distance: 1000,
                        duration: 600, avg_speed: 6, dominant_mode: Track.dominant_modes.fetch(mode.to_s),
                        created_at: STAMP - 86_400, updated_at: STAMP - 86_400 }])
  end

  def release_segment(id, track_id, offset, mode, corrected_at: nil, source: 'inferred')
    TrackSegment.insert_all!([{ id:, track_id:, transportation_mode: TrackSegment.transportation_modes.fetch(mode.to_s),
                               start_at: Time.at(BASE + offset).utc, end_at: Time.at(BASE + offset + 100).utc,
                               corrected_at:, source:, distance: 6000, duration: 100, avg_speed: 3.25,
                               confidence: 1, confidence_score: 0.7, created_at: STAMP - 86_400,
                               updated_at: STAMP - 86_400 }])
  end

  def release_track_snapshot(connection = ActiveRecord::Base.connection)
    fields = Track.column_names - %w[original_path map_matched_at map_matching_data map_matching_input_digest
                                     map_matching_status matched_path]
    tracks = connection.select_all("SELECT #{fields.join(', ')}, encode(ST_AsEWKB(original_path), 'hex') AS ewkb " \
                                   "FROM tracks WHERE id IN (#{TRACK_IDS.join(',')}) ORDER BY id").to_a
    tracks.each { |row| row['dominant_mode'] = Track.dominant_modes.key(row.fetch('dominant_mode')) }
    segments = connection.select_all("SELECT * FROM track_segments WHERE track_id IN (#{TRACK_IDS.join(',')}) " \
                                     'ORDER BY track_id, id').to_a
    source_value('tracks' => tracks, 'segments' => segments)
  end

  def capture_release_import_vectors
    require Rails.root.join('db/migrate/20260125100000_enqueue_transportation_mode_backfill_jobs')
    require Rails.root.join('db/migrate/20260925100100_reenqueue_transportation_mode_backfills')
    vectors = %w[integer_historical text_historical integer_unreleased integer_no_tracks].map do |profile|
      import_release_isolated { release_import_vector(profile) }
    end
    { 'version' => 1, 'vectors' => vectors }
  end

  def release_import_vector(profile)
    connection = ActiveRecord::Base.connection
    reports = []
    allow(Rails.logger).to receive(:error).and_wrap_original do |original, message|
      reports << message.lines.first.strip
      original.call(message)
    end
    user, import = NormalImportFormatsSupport.owner!('UTC')
    user.update_columns(deleted_at: nil)
    import.update_columns(source: 0)
    [1, 2, 3, 6, 10, nil].each_with_index do |source, index|
      Import.insert_all!([{ id: 987_102 + index, user_id: user.id, name: "a12rel-vector-#{index}", source:,
                           created_at: STAMP, updated_at: STAMP }])
    end
    if profile == 'text_historical'
      search_path = connection.select_value('SHOW search_path')
      connection.execute('CREATE SCHEMA a12rel_source_vectors')
      connection.execute('CREATE TABLE a12rel_source_vectors.users(id bigint PRIMARY KEY, deleted_at timestamp)')
      connection.execute('CREATE TABLE a12rel_source_vectors.imports' \
                         '(id bigint PRIMARY KEY, source text, user_id bigint)')
      connection.execute('INSERT INTO a12rel_source_vectors.users VALUES (987001,NULL),(987002,NULL),(987003,NOW())')
      sources = TransportationModes::ActivityBackfiller::SUPPORTED_SOURCES + ['csv', nil]
      sources.each_with_index do |source, index|
        connection.execute('INSERT INTO a12rel_source_vectors.imports VALUES ' \
                           "(#{987_101 + index},#{connection.quote(source)},#{index == 4 ? 987_003 : 987_001})")
      end
      connection.execute('SET search_path = a12rel_source_vectors, public')
      EnqueueTransportationModeBackfillJobs.new.up
    elsif profile == 'integer_historical'
      EnqueueTransportationModeBackfillJobs.new.up
    else
      release_track(TRACK_IDS.first, 0, :driving) unless profile == 'integer_no_tracks'
      ReenqueueTransportationModeBackfills.new.up
    end
    { 'id' => profile, 'jobs' => source_jobs, 'reported' => reports }
  ensure
    if search_path
      connection.execute("SET search_path = #{search_path}")
      connection.execute('DROP SCHEMA a12rel_source_vectors CASCADE')
    end
  end
end
