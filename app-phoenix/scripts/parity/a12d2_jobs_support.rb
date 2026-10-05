# frozen_string_literal: true

require 'sidekiq/job_retry'

module A12d2JobsSupport
  NOW = Time.utc(2026, 10, 4, 12)
  UUID = '00000000-0000-4000-8000-000000480001'
  USER_ID = 48_101
  OTHER_ID = 48_102
  PLACE_ID = 48_201
  FAMILY_ID = 48_401
  SEQUENCES = %w[users places visits families family_memberships notifications points trip_sources
                 achievement_progresses tags taggings place_visits].freeze
  CASES = {
    'Tracks::BackfillGenerationJob' => %w[empty nil_only lookback_boundary berlin_dst tokyo utc cap merge
                                          missing_user deleted_user repeat scope error],
    'Tracks::ThrottledBackfillJob' => %w[occupied gap exact_cursor empty schedule active_ttl backoff_ttl
                                         missing_user deleted_user repeat scope error],
    'AirTrail::SyncSchedulingJob' => %w[selection batches repeat scope error],
    'TeslaMate::SyncSchedulingJob' => %w[selection batches repeat scope error],
    'Trek::SyncSchedulingJob' => %w[selection inherited self_hosted batches repeat scope error],
    'Families::AutoCreationJob' => %w[defaults consent retained_expiry expired_sharing self_hosted lite
                                      existing_member existing_creator missing_user deleted_user notice_error
                                      creation_error sync_error repeat scope error],
    'Families::MemberSyncJob' => %w[grant lapse marked notify_false nil_owner_date downgrade own_live
                                    self_hosted missing_family repeat scope member_error error],
    'Places::NameFetchingJob' => %w[unlocked locked geodata_disabled empty missing properties_empty transient
                                    tls unexpected repeat scope error],
    'Places::BulkNameFetchingJob' => %w[selection batches repeat scope error],
    'Places::DeleteIfOrphanJob' => %w[delete hidden declined active tagged manual waypoint noted whitespace_note
                                      missing fk repeat scope error],
    'Places::OrphanCleanupJob' => %w[delete hidden declined active tagged manual waypoint noted whitespace_note
                                     missing_user deleted_user batches fk repeat scope error],
    'Achievements::BulkCheckJob' => %w[selection stale notify_false force batches repeat scope error]
  }.freeze
  OWNER_KEYS = %w[command:tracks.backfill command:tracks.throttled_backfill command:tracks.generate_range
                  command:imports.airtrail_flights command:families.auto_create command:families.member_sync
                  command:mail.family_lapse command:places.name_fetch command:places.bulk_name_fetch
                  command:places.delete_if_orphan command:places.orphan_cleanup command:achievements.bulk_check
                  command:achievements.check cron:airtrail_flight_import_job cron:teslamate_sync_job
                  cron:trek_sync_job cron:achievements_bulk_check_job].freeze
  SCHEDULE_CASES = {
    'BulkVisitsSuggestingJob' => %w[cron_defaults explicit singular union disabled selection nil_count nil_bounds
                                    error berlin_dst berlin_fall tokyo utc year_chunks future string_bounds],
    'Points::NightlyReverseGeocodingJob' => %w[selection disabled dedup batches repeat error],
    'PendingImports::CleanupJob' => %w[expired expiry_boundary fresh claimed_old seven_day_boundary
                                       claimed_recent shared_expired shared_claimed missing_file missing_object
                                       failed_delete]
  }.freeze
  SCHEDULE_SEQUENCES = (SEQUENCES + %w[instance_settings pending_imports imports active_storage_blobs
                                       active_storage_attachments active_storage_variant_records]).freeze

  def capture_schedule_parents
    classes = SCHEDULE_CASES.to_h do |name, profiles|
      cases = profiles.map do |profile|
        schedule_isolated(profile) do
          method = { 'BulkVisitsSuggestingJob' => :schedule_visits,
                     'Points::NightlyReverseGeocodingJob' => :schedule_geocoding,
                     'PendingImports::CleanupJob' => :schedule_pending }.fetch(name)
          { 'id' => profile, 'now' => Time.current.iso8601(6), 'ambient_zone' => Time.zone.tzinfo.name,
            'owner' => 'sidekiq' }.merge(send(method, profile))
        end
      end
      job = name.constantize.new
      [name, { 'queue' => job.queue_name, 'sidekiq_retry' => name.constantize.get_sidekiq_options.fetch('retry'),
               'cases' => cases }]
    end
    { 'version' => 1, 'classes' => classes }
  end

  def schedule_isolated(profile)
    connection = ActiveRecord::Base.connection
    sequences = source_sequences_for(SCHEDULE_SEQUENCES, connection)
    redis = schedule_redis_snapshot
    result = nil
    RSpec::Mocks.with_temporary_scope do
      source_stubs
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      ActiveRecord::Base.transaction(requires_new: true) do
        phoenix_tables!
        %w[command:visits.suggest command:geocoding.reverse_point command:geocoding.reverse_place].each do |key|
          JobOwnership.put!(key, :sidekiq, pinned: true, by: 'a12d3-source')
        end
        without_phoenix_state!
        sequences.each_key { connection.execute("SELECT setval('#{_1}_id_seq', 48500, false)") }
        ActiveSupport::IsolatedExecutionState[:job_commands_inline] = true
        stamp = case profile
                when 'berlin_dst' then Time.utc(2024, 4, 1, 12)
                when 'berlin_fall' then Time.utc(2024, 10, 28, 12)
                else NOW
                end
        zone = { 'tokyo' => 'Asia/Tokyo', 'utc' => 'Etc/UTC' }.fetch(profile, 'Europe/Berlin')
        travel_to(stamp) { Time.use_zone(zone) { I18n.with_locale(:en) { result = yield } } }
        raise ActiveRecord::Rollback
      end
    end
    result
  ensure
    ActiveSupport::IsolatedExecutionState[:job_commands_inline] = nil
    source_restore_sequences(connection, sequences)
    schedule_restore_redis(redis)
    InstanceSettings::Resolver.reset!
    PhoenixSchema.reset!
    clear_enqueued_jobs
  end

  def source_sequences_for(tables, connection)
    tables.filter_map do |table|
      next unless connection.select_value("SELECT to_regclass('#{table}_id_seq') IS NOT NULL")

      [table, connection.select_one("SELECT last_value, is_called FROM #{table}_id_seq")]
    end.to_h
  end

  def schedule_redis_snapshot
    Sidekiq.redis do |redis|
      (48_301..49_304).to_h do |id|
        key = Point.geocode_dedup_key(id)
        ttl = redis.pttl(key)
        [key, [redis.dump(key), ttl.positive? ? Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000 + ttl : ttl]]
      end
    end
  end

  def schedule_restore_redis(snapshot)
    return unless snapshot

    Sidekiq.redis do |redis|
      snapshot.each do |key, (bytes, deadline)|
        redis.del(key)
        next unless bytes

        ttl = deadline == -1 ? 0 : (deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).ceil
        redis.restore(key, ttl, bytes) if ttl >= 0
      end
    end
  end

  def schedule_jobs
    jobs = enqueued_jobs.map do |job|
      { 'class' => job.fetch(:job).name, 'queue' => job.fetch(:queue),
        'arguments' => source_value(ActiveJob::Arguments.deserialize(job.fetch(:args))),
        'serialized_arguments' => job.fetch(:args) }
    end
    jobs.sort_by { |job| [job.fetch('class'), JSON.generate(job.fetch('serialized_arguments'))] }
  end

  def schedule_visits(profile)
    configure_instance_geocoding unless profile == 'disabled'
    user = source_user(points_count: 1)
    other = source_user(OTHER_ID, points_count: 2)
    if profile == 'selection'
      source_user(48_103, points_count: 1, status: :inactive)
      source_user(48_104, points_count: 1, status: :trial)
      source_user(48_105, points_count: 0)
      source_user(48_106, points_count: 1, settings: { 'visits_suggestions_enabled' => 'false' })
      source_user(48_107, points_count: 1).update_columns(deleted_at: Time.current)
      source_user(48_108, points_count: 1, plan: :lite)
      source_user(48_109, points_count: 1, active_until: 1.day.ago)
    end
    if profile == 'nil_count'
      allow_any_instance_of(User).to receive(:points_count) { |row| row.id == user.id ? nil : row[:points_count] }
    end
    arguments = case profile
                when 'singular' then { user_id: user.id }
                when 'union' then { user_ids: [user.id, nil, user.id], user_id: other.id }
                when 'explicit' then { user_ids: [user.id], start_at: 2.days.ago, end_at: 1.day.ago }
                when 'nil_bounds' then { start_at: nil, end_at: nil }
                when 'year_chunks' then { start_at: DateTime.new(2023, 12, 30), end_at: DateTime.new(2026, 1, 2) }
                when 'future' then { start_at: 2.days.from_now, end_at: 1.day.from_now }
                when 'string_bounds' then { start_at: '2024-03-31T00:00:00+01:00',
                                            end_at: '2024-03-31T23:59:59+02:00' }
                else {}
                end
    calls = []
    allow(Visits::TimeChunks).to receive(:new).and_wrap_original do |original, **bounds|
      calls << bounds.transform_values { { 'type' => _1.class.name, 'value' => _1.iso8601(6) } }
      original.call(**bounds)
    end
    if profile == 'error'
      allow(VisitSuggestingJob).to receive(:perform_later).and_raise('fixture visit publication failure')
    end
    parent = BulkVisitsSuggestingJob.new(**arguments)
    effects = source_effects do
      parent.perform(**arguments)
      nil
    end
    serialized_parent = parent.serialize.slice('job_class', 'job_id', 'queue_name', 'arguments')
    effects.merge('input' => source_value(arguments), 'serialized_parent' => serialized_parent,
                  'time_chunks_calls' => source_value(calls), 'jobs' => schedule_jobs,
                  'users' => User.unscoped.where(id: 48_101..48_109).order(:id).map do |row|
                    { 'id' => row.id, 'status' => row.status, 'plan' => row.plan, 'points_count' => row.points_count,
                      'suggestions' => row.safe_settings.visits_suggestions_enabled?, 'deleted' => row.deleted? }
                  end)
  end

  def schedule_geocoding(profile)
    configure_instance_geocoding unless profile == 'disabled'
    user = source_user
    other = source_user(OTHER_ID)
    source_point(user.id, NOW.to_i)
    source_point(user.id, NOW.to_i + 1, id: 48_302, reverse_geocoded_at: Time.current)
    source_point(other.id, NOW.to_i + 2, id: 48_303)
    other.update_columns(deleted_at: Time.current) if profile == 'selection'
    if profile == 'batches'
      Point.insert_all!(Array.new(1001) do |index|
        { id: 48_304 + index, user_id: user.id, timestamp: NOW.to_i + index + 3, lonlat: 'POINT(13 52)',
          created_at: Time.current, updated_at: Time.current }
      end)
    end
    keys = Point.not_reverse_geocoded.order(:id).pluck(:id).map { Point.geocode_dedup_key(_1) }
    if profile == 'dedup'
      Sidekiq.redis { |redis| keys.each { redis.set(_1, 'synthetic-claim', ex: Point::GEOCODE_DEDUP_TTL) } }
    end
    batches = []
    allow(Geocoding::ReverseCommands).to receive(:enqueue_points).and_wrap_original do |original, id, ids, **options|
      batches << { 'user_id' => id, 'point_ids' => ids, 'force' => options.fetch(:force) }
      raise 'fixture geocoding publication failure' if profile == 'error'

      original.call(id, ids, **options)
    end
    invalidated = []
    allow(Cache::InvalidateUserCaches).to receive(:new).and_wrap_original do |original, id, **options|
      invalidated << id
      original.call(id, **options)
    end
    deletes = []
    allow(Rails.cache).to receive(:delete).and_wrap_original do |original, key, *args|
      deletes << key
      original.call(key, *args)
    end
    effects = source_effects do
      Points::NightlyReverseGeocodingJob.new.perform
      Points::NightlyReverseGeocodingJob.new.perform if profile == 'repeat'
      nil
    end
    effects.merge('batches' => batches, 'invalidated_user_ids' => invalidated, 'cache_deletes' => deletes,
                  'remaining_claims' => Sidekiq.redis { |redis| keys.select { redis.exists(_1).positive? } },
                  'jobs' => schedule_jobs)
  end

  def schedule_pending(profile)
    user = source_user
    attributes = { id: 48_901, original_filename: 'synthetic.zip', origin: 'https://example.invalid',
                   expires_at: 1.day.ago }
    attributes[:expires_at] = Time.current if profile == 'expiry_boundary'
    attributes[:expires_at] = 1.day.from_now if profile == 'fresh'
    if %w[claimed_old shared_claimed seven_day_boundary claimed_recent].include?(profile)
      attributes[:claimed_at] = case profile
                                when 'seven_day_boundary' then 7.days.ago
                                when 'claimed_recent' then 6.days.ago
                                else 8.days.ago
                                end
      attributes[:claimed_by_user_id] = user.id
    end
    pending = PendingImport.create!(**attributes)
    blob = nil
    object_path = nil
    original_bytes = nil
    unless profile == 'missing_file'
      key = "a12d3pending#{profile.delete('_')}"
      service = ActiveStorage::Blob.services.fetch('test')
      object_path = service.send(:path_for, key)
      original_bytes = File.binread(object_path) if File.file?(object_path)
      content = 'synthetic pending-import bytes'
      blob = ActiveStorage::Blob.create_before_direct_upload!(key:, filename: 'synthetic.zip',
                                                              byte_size: content.bytesize, checksum: Digest::MD5.base64digest(content),
                                                              content_type: 'application/zip', service_name: 'test')
      service.upload(key, StringIO.new(content))
      pending.file.attach(blob)
      service.delete(key) if profile == 'missing_object'
    end
    import = nil
    if %w[shared_expired shared_claimed].include?(profile)
      import = create(:import, id: 48_902, user:, skip_background_processing: true)
      import.file.attach(blob)
    end
    if profile == 'failed_delete'
      allow(blob.service).to receive(:delete).with(blob.key).and_raise(IOError,
                                                                       'fixture object delete failure')
    end
    effects = source_effects do
      PendingImports::CleanupJob.new.perform
      nil
    end
    effects.merge('input' => source_value(attributes), 'jobs' => schedule_jobs,
                  'pending_exists' => PendingImport.exists?(pending.id),
                  'blob_exists' => blob ? ActiveStorage::Blob.exists?(blob.id) : nil,
                  'object_exists' => blob&.service&.exist?(blob.key),
                  'attachments' => blob ? blob.attachments.order(:id).pluck(:record_type, :record_id) : [],
                  'import_attached' => import ? import.reload.file.attached? : nil)
  ensure
    if object_path
      if original_bytes
        FileUtils.mkdir_p(File.dirname(object_path))
        File.binwrite(object_path, original_bytes)
      else
        FileUtils.rm_f(object_path)
      end
    end
  end

  def capture_jobs
    classes = CASES.to_h do |name, profiles|
      cases = profiles.map do |profile|
        source_isolated(name, profile) { source_case(name, profile) }
      end
      [name, { 'retry' => source_retry(name.constantize), 'cases' => cases }]
    end
    { 'version' => 1, 'classes' => classes, 'races' => %i[single sweep].to_h { [_1.to_s, capture_orphan_race(_1)] } }
  end

  def source_retry(job)
    expect(job.rescue_handlers).to eq([])
    expect(Sidekiq.default_job_options.fetch('retry')).to be(true)
    expect(Sidekiq.default_configuration[:max_retries]).to be_nil
    {
      'sidekiq_version' => Gem.loaded_specs.fetch('sidekiq').version.to_s,
      'activejob_version' => Gem.loaded_specs.fetch('activejob').version.to_s,
      'activejob_handlers' => [], 'sidekiq_retry' => true,
      'max_retries' => Sidekiq::JobRetry::DEFAULT_MAX_RETRY_ATTEMPTS,
      'max_attempts' => Sidekiq::JobRetry::DEFAULT_MAX_RETRY_ATTEMPTS + 1,
      'backoff_seconds' => 'count**4 + 15 + rand(10 * (count + 1))',
      'queue' => job.queue_name,
      'handled_errors_retry' => false, 'escaping_errors_retry' => true
    }
  end

  def source_isolated(name, profile)
    connection = ActiveRecord::Base.connection
    sequences = source_sequences(connection)
    result = nil
    RSpec::Mocks.with_temporary_scope do
      source_stubs
      ActiveRecord::Base.transaction(requires_new: true) do
        phoenix_tables!
        OWNER_KEYS.each { JobOwnership.put!(_1, :sidekiq, pinned: true, by: 'a12d2-source') }
        JobOwnership.put!('command:users.destroy', :oban, pinned: true, by: 'a12d2-sentinel')
        without_phoenix_state!
        %w[track_backfill_ranges track_backfill_walks].each do |table|
          connection.execute("DROP TABLE IF EXISTS phoenix.#{table}")
        end
        PhoenixSchema.reset!
        SEQUENCES.each do |table|
          next unless sequences.key?(table)

          connection.execute("SELECT setval('#{table}_id_seq', 48500, false)")
        end
        ActiveSupport::IsolatedExecutionState[:job_commands_inline] = true
        stamp = name == 'Tracks::BackfillGenerationJob' && profile == 'berlin_dst' ? Time.utc(2024, 4, 1, 12) : NOW
        travel_to(stamp) do
          Time.use_zone(if profile == 'tokyo'
                          'Asia/Tokyo'
                        else
                          profile == 'utc' ? 'Etc/UTC' : 'Europe/Berlin'
                        end) do
            I18n.with_locale(:en) { result = yield }
          end
        end
        raise ActiveRecord::Rollback
      end
    end
    result
  ensure
    ActiveSupport::IsolatedExecutionState[:job_commands_inline] = nil
    source_restore_sequences(connection, sequences)
    source_redis_cleanup
    PhoenixSchema.reset!
    clear_enqueued_jobs
  end

  def source_stubs
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
    allow(SecureRandom).to receive(:uuid).and_return(UUID)
    @source_reports = []
    allow(ExceptionReporter).to receive(:call) { |error, *_| @source_reports << error.class.name }
  end

  def source_sequences(connection)
    SEQUENCES.filter_map do |table|
      next unless connection.select_value("SELECT to_regclass('#{table}_id_seq') IS NOT NULL")

      [table, connection.select_one("SELECT last_value, is_called FROM #{table}_id_seq")]
    end.to_h
  end

  def source_restore_sequences(connection, sequences)
    sequences&.each do |table, state|
      connection.execute("SELECT setval('#{table}_id_seq', #{state.fetch('last_value')}, " \
                         "#{connection.quote(state.fetch('is_called'))})")
    end
  end

  def source_redis_cleanup
    Sidekiq.redis do |redis|
      [USER_ID, OTHER_ID].each do |id|
        redis.del("track_backfill_range:user:#{id}", "track_backfill:user:#{id}",
                  "track_throttled_backfill:user:#{id}")
      end
    end
    [USER_ID, OTHER_ID].each do |id|
      Tracks::SessionManager.new(id, UUID).cleanup_session
    end
  end

  def source_case(name, profile)
    method = {
      'Tracks::BackfillGenerationJob' => :source_range,
      'Tracks::ThrottledBackfillJob' => :source_walk,
      'AirTrail::SyncSchedulingJob' => :source_scheduler,
      'TeslaMate::SyncSchedulingJob' => :source_scheduler,
      'Trek::SyncSchedulingJob' => :source_scheduler,
      'Families::AutoCreationJob' => :source_auto_family,
      'Families::MemberSyncJob' => :source_family_sync,
      'Places::NameFetchingJob' => :source_place_name,
      'Places::BulkNameFetchingJob' => :source_place_names,
      'Places::DeleteIfOrphanJob' => :source_orphan,
      'Places::OrphanCleanupJob' => :source_orphan,
      'Achievements::BulkCheckJob' => :source_achievements
    }.fetch(name)
    { 'id' => profile, 'now' => Time.current.iso8601(6), 'ambient_zone' => Time.zone.tzinfo.name,
      'owner' => 'sidekiq', 'sentinel_owner' => 'oban' }.merge(send(method, name.constantize, profile))
  end

  def source_user(id = USER_ID, **attributes)
    create(:user, id:, email: "a12d2-#{id}@example.invalid", password: 'synthetic-password',
                  skip_auto_trial: true, skip_family_sync: true,
                  settings: { 'timezone' => 'Asia/Tokyo', 'locale' => 'de' }, **attributes)
  end

  def source_point(user_id, timestamp, id: 48_301, **attributes)
    Point.insert_all!([{ id:, user_id:, timestamp:, lonlat: 'POINT(13 52)', anomaly: false,
                        created_at: Time.current, updated_at: Time.current }.merge(attributes)])
  end

  def source_place(user, id: PLACE_ID, **attributes)
    create(:place, id:, user:, name: Place::DEFAULT_NAME, source: :photon, **attributes)
  end

  def source_visit(user, place, id: 48_601, **attributes)
    Visit.insert_all!([{ id:, user_id: user.id, place_id: place.id, area_id: nil, name: Place::DEFAULT_NAME,
                        status: Visit.statuses.fetch('suggested'), started_at: Time.current + (id - 48_601),
                        ended_at: 1.hour.from_now + (id - 48_601), duration: 3600, created_at: Time.current,
                        updated_at: Time.current }.merge(attributes)])
    Visit.find(id)
  end

  def source_jobs
    jobs = enqueued_jobs.map do |job|
      { 'class' => job.fetch(:job).name, 'queue' => job.fetch(:queue),
        'arguments' => source_value(ActiveJob::Arguments.deserialize(job.fetch(:args))),
        'due_offset' => job[:at] ? (job[:at] - Time.current.to_f).round(6) : 0 }
    end
    jobs.sort_by { |job| [job.fetch('due_offset'), job.fetch('class'), JSON.generate(job.fetch('arguments'))] }
  end

  def source_value(value)
    case value
    when ActiveSupport::TimeWithZone, Time then value.iso8601(6)
    when Array then value.map { source_value(_1) }
    when Hash then value.transform_keys(&:to_s).transform_values { source_value(_1) }
    when Symbol then value.to_s
    when ActiveRecord::Base then { 'class' => value.class.name, 'id' => value.id }
    when Tracks::SessionManager then { 'session_id' => value.session_id }
    else value
    end
  end

  def source_effects(isolated: false, &work)
    clear_enqueued_jobs
    @source_reports.clear
    result = nil
    error = nil
    begin
      result = isolated ? ActiveRecord::Base.transaction(requires_new: true, &work) : work.call
    rescue StandardError => e
      error = { 'class' => e.class.name, 'message' => e.message }
    end
    { 'result' => source_value(result), 'error' => error, 'reported' => @source_reports.dup, 'jobs' => source_jobs }
  end

  def source_range(job, profile)
    source_user
    source_user(OTHER_ID)
    user = User.find(USER_ID)
    user.update_columns(deleted_at: Time.current) if profile == 'deleted_user'
    user.delete if profile == 'missing_user'
    historical = Time.current.to_i - (profile == 'berlin_dst' ? 1.day.to_i : 2.days.to_i)
    timestamps = case profile
                 when 'empty' then []
                 when 'nil_only' then [nil, nil]
                 when 'lookback_boundary' then [Time.current.to_i - 6.hours.to_i]
                 when 'cap' then [historical, Time.current.to_i]
                 else [historical, historical + 3600]
                 end
    source_redis_cleanup
    Tracks::BackfillScheduler.new(OTHER_ID, [historical - 1.day.to_i]).call
    if profile == 'error'
      allow(Tracks::ParallelGeneratorJob).to receive(:perform_later).and_raise('fixture publication failure')
    end
    effects = source_effects do
      Tracks::BackfillScheduler.new(USER_ID, timestamps).call
      Tracks::BackfillScheduler.new(USER_ID, [historical - 1.day.to_i, historical + 7200]).call if profile == 'merge'
      range = Sidekiq.redis { _1.zrange("track_backfill_range:user:#{USER_ID}", 0, -1).map(&:to_i) }
      @range_before = range.empty? ? nil : [range.first, range.last]
      job.new.perform(USER_ID)
      if profile == 'repeat'
        Tracks::BackfillScheduler.new(USER_ID, timestamps).call
        job.new.perform(USER_ID)
      end
      nil
    end
    effects.merge('input' => { 'user_id' => USER_ID, 'user_zone' => 'Asia/Tokyo', 'timestamps' => timestamps },
                  'range' => @range_before,
                  'range_ttl' => Sidekiq.redis { _1.ttl("track_backfill_range:user:#{USER_ID}") },
                  'remaining_range' => Sidekiq.redis do
                    _1.zrange("track_backfill_range:user:#{USER_ID}", 0, -1).map(&:to_i)
                  end,
                  'other_range' => Sidekiq.redis do
                    _1.zrange("track_backfill_range:user:#{OTHER_ID}", 0, -1).map(&:to_i)
                  end)
  end

  def source_walk(job, profile)
    user = source_user
    source_user(OTHER_ID)
    cursor = Time.current.to_i
    last = cursor - (profile == 'gap' ? 100.days.to_i : 3600)
    unless %w[empty backoff_ttl missing_user deleted_user schedule].include?(profile)
      source_point(USER_ID, last)
      source_point(USER_ID, last - 3600, id: 48_302)
      source_point(USER_ID, cursor, id: 48_303)
      source_point(OTHER_ID, cursor - 1, id: 48_304)
    end
    user.update_columns(deleted_at: Time.current) if profile == 'deleted_user'
    user.delete if profile == 'missing_user'
    source_redis_cleanup
    Sidekiq.redis { _1.set(job.redis_key(OTHER_ID), 1, ex: 1234) }
    @generation_calls = []
    allow(Tracks::ParallelGenerator).to receive(:new).and_wrap_original do |original, owner, **options|
      @generation_calls << source_value(options.merge(user_id: owner.id))
      generator = original.call(owner, **options)
      allow(generator).to receive(:call).and_raise('fixture generation failure') if profile == 'error'
      generator
    end
    effects = source_effects do
      if profile == 'schedule'
        [job.schedule(user), job.schedule(user)]
      else
        job.new.perform(USER_ID, %w[exact_cursor repeat scope error].include?(profile) ? cursor : nil)
        job.new.perform(USER_ID, cursor) if profile == 'repeat'
        nil
      end
    end
    effects.merge('input' => { 'user_id' => USER_ID, 'cursor' => cursor, 'eligible_maximum' => last },
                  'generation_calls' => @generation_calls,
                  'ttl' => Sidekiq.redis { _1.ttl(job.redis_key(USER_ID)) },
                  'other_key' => Sidekiq.redis { _1.get(job.redis_key(OTHER_ID)) })
  end

  def source_scheduler(job, profile)
    good = source_user(status: :inactive)
    foreign = source_user(OTHER_ID, plan: :lite, status: :inactive)
    kind = job.name.split('::').first
    settings = case kind
               when 'AirTrail' then { 'airtrail_url' => 'https://airtrail.example.invalid', 'airtrail_api_key' => 'synthetic' }
               when 'TeslaMate' then { 'teslamate_url' => 'https://teslamate.example.invalid' }
               else {}
               end
    good.update_columns(settings: good.settings.merge(settings))
    if kind == 'Trek'
      good.update_columns(plan: User.plans.fetch('pro'), status: User.statuses.fetch('active'))
      source_trip(good.id, 48_701)
      source_trip(foreign.id, 48_702)
      source_trip(good.id, 48_703, status: TripSource.statuses.fetch('disabled'))
      source_trip(good.id, 48_704, provider: 'other')
      if profile == 'inherited'
        good.update_columns(plan: User.plans.fetch('lite'))
        owner = source_user(48_103, plan: :family)
        family = create(:family, id: FAMILY_ID, name: 'Synthetic family', creator: owner, access_until: 1.day.from_now)
        create(:family_membership, id: 48_501, family:, user: good)
      end
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true) if profile == 'self_hosted'
    else
      blank_settings = kind == 'AirTrail' ? { 'airtrail_api_key' => '' } : { 'teslamate_url' => '' }
      foreign.update_columns(settings: settings.merge(blank_settings))
      null_user = source_user(48_103)
      null_user.update_columns(settings: settings.transform_values { nil })
      if kind == 'AirTrail'
        blank_url = source_user(48_104)
        blank_url.update_columns(settings: settings.merge('airtrail_url' => ''))
      end
    end
    if profile == 'batches'
      source_bulk_users(good, 2000)
      2000.times { |index| source_trip(49_000 + index, 49_000 + index) } if kind == 'Trek'
    end
    leaf = { 'AirTrail' => AirTrail::ImportFlightsJob, 'TeslaMate' => TeslaMate::SyncJob,
             'Trek' => Trek::SyncJob }.fetch(kind)
    allow(leaf).to receive(:perform_later).and_raise('fixture leaf publication failure') if profile == 'error'
    effects = source_effects do
      job.new.perform
      job.new.perform if profile == 'repeat'
      nil
    end
    effects.merge('input' => { 'configured_user' => good.id, 'foreign_user' => foreign.id,
                              'url_configured' => kind != 'Trek', 'key_configured' => kind == 'AirTrail',
                              'extra_eligible_users' => profile == 'batches' ? 2000 : 0 })
  end

  def source_bulk_users(template, count)
    base = template.attributes.except('id', 'email', 'encrypted_password', 'api_key', 'secret_key')
    User.insert_all!(Array.new(count) do |index|
      base.merge('id' => 49_000 + index, 'email' => "a12d2-batch-#{index}@example.invalid",
                 'encrypted_password' => '')
    end)
  end

  def source_trip(user_id, id, **attributes)
    TripSource.insert_all!([{ id:, user_id:, provider: 'trek', status: TripSource.statuses.fetch('active'),
                             base_url: "https://trek-#{id}.example.invalid", api_key: 'synthetic',
                             created_at: Time.current, updated_at: Time.current }.merge(attributes)])
  end

  def source_auto_family(job, profile)
    user = source_user(plan: :family)
    source_user(OTHER_ID, plan: :lite)
    sharing = { 'enabled' => false, 'started_at' => 2.days.ago.iso8601, 'share_history' => true,
                'history_window' => '30d', 'history_before_sharing' => profile == 'consent',
                'duration' => '6h', 'expires_at' => 2.hours.from_now.iso8601 }
    sharing['expires_at'] = 1.hour.ago.iso8601 if profile == 'expired_sharing'
    user.update_columns(settings: user.settings.merge('family' => { 'location_sharing' => sharing })) if
      %w[consent retained_expiry expired_sharing].include?(profile)
    user.update_columns(plan: User.plans.fetch('lite')) if profile == 'lite'
    user.update_columns(deleted_at: Time.current) if profile == 'deleted_user'
    user.delete if profile == 'missing_user'
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true) if profile == 'self_hosted'
    if %w[existing_member existing_creator].include?(profile)
      family = create(:family, id: FAMILY_ID, name: 'Synthetic family', creator: user)
      create(:family_membership, id: 48_501, family:, user:, role: :owner) if profile == 'existing_member'
    end
    allow(Notification).to receive(:create!).and_raise('fixture notice failure') if profile == 'notice_error'
    allow(Family).to receive(:create!).and_raise('fixture creation failure') if profile == 'creation_error'
    if %w[sync_error error].include?(profile)
      allow_any_instance_of(Families::SyncMembers).to receive(:call).and_raise('fixture sync failure')
    end
    input = { 'user_id' => user.id, 'settings' => user.settings, 'plan' => profile == 'lite' ? 'lite' : 'family' }
    effects = source_effects(isolated: true) do
      job.new.perform(USER_ID)
      job.new.perform(USER_ID) if profile == 'repeat'
      nil
    end
    families = Family.where(creator_id: USER_ID).order(:id).pluck(:id, :creator_id, :name, :access_until)
    memberships = Family::Membership.where(user_id: USER_ID).order(:id).pluck(:family_id, :user_id, :role)
    effects.merge('input' => input, 'families' => source_value(families), 'memberships' => memberships,
                  'settings' => User.find_by(id: USER_ID)&.settings,
                  'notifications' => Notification.where(user_id: USER_ID).order(:id).pluck(:kind, :title, :content),
                  'foreign_family' => Family::Membership.exists?(user_id: OTHER_ID))
  end

  def source_family_sync(job, profile)
    owner = source_user(plan: :family, active_until: 2.days.from_now)
    member = source_user(OTHER_ID, plan: :lite, status: :inactive, active_until: 1.day.ago)
    foreign = source_user(48_103, plan: :pro, subscription_source: :paddle)
    family = create(:family, id: FAMILY_ID, name: 'Synthetic family', creator: owner, access_until: 1.day.from_now)
    create(:family_membership, id: 48_501, family:, user: owner, role: :owner)
    create(:family_membership, id: 48_502, family:, user: member)
    create(:family_membership, id: 48_503, family:, user: foreign)
    member.update_columns(subscription_source: User.subscription_sources.fetch('apple_iap')) if profile == 'lapse'
    Families::LapseNotice.mark(member) if %w[grant marked].include?(profile)
    if %w[lapse marked notify_false error member_error].include?(profile)
      owner.update_columns(active_until: 2.days.ago)
      family.update_columns(access_until: 2.days.ago)
    end
    owner.update_columns(active_until: nil) if profile == 'nil_owner_date'
    owner.update_columns(plan: User.plans.fetch('pro'), active_until: 5.days.from_now) if profile == 'downgrade'
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true) if profile == 'self_hosted'
    allow(Families::LapseNotice).to receive(:notified?).and_raise('fixture member failure') if profile == 'member_error'
    if profile == 'error'
      allow(JobCommands).to receive(:produce).and_call_original
      allow(JobCommands).to receive(:produce).with('mail.family_lapse', anything,
                                                   anything).and_raise('fixture mail publication failure')
    end
    effects = source_effects(isolated: true) do
      if profile == 'notify_false'
        Families::SyncMembers.new(family:, notify: false).call
      else
        job.new.perform(profile == 'missing_family' ? 0 : family.id)
        job.new.perform(family.id) if profile == 'repeat'
      end
      nil
    end
    effects.merge('input' => { 'family_id' => family.id, 'owner_id' => owner.id, 'member_id' => member.id },
                  'access_until' => source_value(family.reload.access_until),
                  'members' => [owner, member, foreign].map do |row|
                    fresh = row.reload
                    source_value(fresh.attributes.slice('id', 'plan', 'status', 'active_until', 'subscription_source',
                                                        'settings'))
                  end)
  end

  def source_place_name(job, profile)
    user = source_user
    other = source_user(OTHER_ID)
    place = source_place(user)
    foreign = source_place(other, id: PLACE_ID + 1)
    place.update_columns(name: 'Old machine name', name_locked_at: nil)
    place.update_columns(name: 'Owner name', name_locked_at: Time.current) if profile == 'locked'
    first = source_visit(user, place)
    source_visit(user, place, id: 48_602, name: 'Custom visit')
    source_visit(user, foreign, id: 48_603)
    source_visit(user, place, id: 48_604, name: place.name)
    properties = { 'name' => ' yes ', 'street' => ' Synthetic street ', 'housenumber' => '9',
                   'city' => 'Synthetic city', 'state' => 'Synthetic city', 'country' => 'Testland' }
    data = { 'properties' => properties, 'geometry' => { 'type' => 'Point', 'coordinates' => [13, 52] } }
    configure_instance_geocoding
    allow(Geocoder).to receive(:search).and_return([double(data:)])
    allow(Geocoder).to receive(:search).and_return([]) if profile == 'empty'
    allow(Geocoder).to receive(:search).and_return([double(data: {})]) if profile == 'properties_empty'
    if %w[transient tls unexpected error].include?(profile)
      error = case profile
              when 'transient' then Geocoder::LookupTimeout.new('fixture timeout')
              when 'tls' then OpenSSL::SSL::SSLError.new('unexpected eof while reading')
              else StandardError.new('fixture provider failure')
              end
      allow(Geocoder).to receive(:search).and_raise(error)
    end
    allow(DawarichSettings).to receive(:store_geodata?).and_return(false) if profile == 'geodata_disabled'
    effects = source_effects do
      job.new.perform(profile == 'missing' ? 0 : place.id)
      job.new.perform(place.id) if profile == 'repeat'
      nil
    end
    fields = %w[id name city country geodata source name_locked_at]
    effects.merge('input' => { 'place_id' => place.id, 'user_id' => user.id, 'properties' => properties },
                  'place' => source_value(place.reload.attributes.slice(*fields)),
                  'visit_names' => Visit.where(id: [first.id, 48_602, 48_603, 48_604]).order(:id).pluck(:id, :name),
                  'foreign_place_name' => foreign.reload.name)
  end

  def source_place_names(job, profile)
    user = source_user
    other = source_user(OTHER_ID)
    source_place(user)
    source_place(other, id: PLACE_ID + 1)
    source_place(other, id: PLACE_ID + 2).update_columns(name: 'Custom name')
    if profile == 'batches'
      Place.insert_all!(Array.new(2000) do |index|
        { id: 49_000 + index, user_id: user.id, name: Place::DEFAULT_NAME, lonlat: 'POINT(13 52)',
          latitude: 52, longitude: 13,
          source: Place.sources.fetch('photon'), created_at: Time.current, updated_at: Time.current }
      end)
    end
    if profile == 'error'
      allow(Places::NameFetchingJob).to receive(:perform_later).and_raise('fixture name publication failure')
    end
    source_effects do
      job.new.perform
      job.new.perform if profile == 'repeat'
      nil
    end.merge('input' => { 'default_place_ids' => [PLACE_ID, PLACE_ID + 1], 'custom_place_id' => PLACE_ID + 2,
                          'extra_default_places' => profile == 'batches' ? 2000 : 0 })
  end

  def source_orphan(job, profile)
    user = source_user
    other = source_user(OTHER_ID)
    place = source_place(user)
    foreign = source_place(other, id: PLACE_ID + 1)
    case profile
    when 'manual' then place.update_columns(source: Place.sources.fetch('manual'))
    when 'waypoint' then place.update_columns(source: Place.sources.fetch('gpx_waypoint'))
    when 'noted' then place.update_columns(note: 'Retain')
    when 'whitespace_note' then place.update_columns(note: ' ')
    when 'active' then source_visit(user, place)
    when 'hidden' then source_visit(user, place, deleted_at: Time.current)
    when 'declined' then source_visit(user, place, status: Visit.statuses.fetch('declined'))
    when 'tagged'
      tag = create(:tag, id: 48_801, user:, name: 'Synthetic')
      place.tags << tag
    end
    if profile == 'batches'
      Place.insert_all!(Array.new(1000) do |index|
        { id: 49_000 + index, user_id: user.id, name: Place::DEFAULT_NAME, lonlat: 'POINT(13 52)',
          latitude: 52, longitude: 13,
          source: Place.sources.fetch('photon'), created_at: Time.current, updated_at: Time.current }
      end)
    end
    if profile == 'fk'
      allow(Visit).to receive(:where).and_call_original
      allow(Visit).to receive(:where).with(place_id: anything).and_raise(ActiveRecord::InvalidForeignKey,
                                                                         'fixture FK failure')
    elsif profile == 'error'
      allow(Place).to receive(:find_by).and_call_original
      allow(Place.connection).to receive(:exec_query).and_call_original
      if job == Places::DeleteIfOrphanJob
        allow(Place).to receive(:find_by).with(id: place.id).and_raise('fixture deletion failure')
      end
      if job == Places::OrphanCleanupJob
        allow(Place.connection).to receive(:exec_query).with(anything, 'OrphanCleanup victims', anything)
                                                       .and_raise('fixture deletion failure')
      end
    end
    user.update_columns(deleted_at: Time.current) if profile == 'deleted_user'
    victim_id = profile == 'missing' ? 0 : place.id
    effects = source_effects do
      if job == Places::DeleteIfOrphanJob
        first = job.new.perform(victim_id)
        second = job.new.perform(victim_id) if profile == 'repeat'
        profile == 'repeat' ? [first, second] : first
      else
        job.new.perform(profile == 'missing_user' ? 0 : user.id)
        job.new.perform(user.id) if profile == 'repeat'
        nil
      end
    end
    effects.merge('input' => { 'user_id' => user.id, 'place_id' => victim_id },
                  'place_exists' => Place.exists?(place.id), 'other_place_exists' => Place.exists?(foreign.id),
                  'remaining_batch_places' => Place.where(id: 49_000...50_000).count,
                  'visit_place_ids' => Visit.where(id: 48_601).pluck(:place_id))
  end

  def source_achievements(job, profile)
    user = source_user
    other = source_user(OTHER_ID, status: :inactive)
    trial = source_user(48_103, status: :trial, plan: :lite)
    anomaly = source_user(48_104)
    incomplete = source_user(48_105)
    deleted = source_user(48_106)
    deleted.update_columns(deleted_at: Time.current)
    [user, other, trial, deleted].each_with_index do |row, index|
      source_point(row.id, Time.current.to_i - 3600, id: 48_301 + index)
    end
    source_point(anomaly.id, Time.current.to_i - 3600, id: 48_305, anomaly: true)
    source_point(incomplete.id, Time.current.to_i - 3600, id: 48_306, lonlat: nil)
    version = Achievements::RegionSetChecker::CALCULATION_VERSION
    Achievements::Progress.create!(user:, achievement_key: 'exploration', state: { 'calculation_version' => version })
    Achievements::Progress.create!(user: trial, achievement_key: 'exploration', state: { 'calculation_version' => 0 })
    if profile == 'batches'
      source_bulk_users(user, 400)
      400.times { |index| source_point(49_000 + index, Time.current.to_i - 3600, id: 49_000 + index) }
    end
    if profile == 'error'
      allow_any_instance_of(Achievements::CheckJob).to receive(:enqueue).and_raise('fixture check publication failure')
    end
    options = { notify: profile != 'notify_false', force: profile == 'force', stale_only: profile == 'stale' }
    source_effects do
      job.new.perform(**options)
      job.new.perform(**options) if profile == 'repeat'
      nil
    end.merge('input' => { 'options' => source_value(options), 'current_user' => user.id, 'stale_user' => trial.id,
                          'inactive_user' => other.id, 'anomaly_user' => anomaly.id, 'incomplete_user' => incomplete.id,
                          'deleted_user' => deleted.id, 'extra_eligible_users' => profile == 'batches' ? 400 : 0 })
  end

  def capture_orphan_race(kind)
    connection = ActiveRecord::Base.connection
    sequences = source_sequences(connection)
    result = nil
    RSpec::Mocks.with_temporary_scope do
      source_stubs
      travel_to(NOW) do
        user = source_user
        place = source_place(user)
        insert_reference = lambda do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do |second|
              expect(second.raw_connection.object_id).not_to eq(connection.raw_connection.object_id)
              source_visit(user, place)
            end
          end.value
        end
        if kind == :single
          allow(Place).to receive(:transaction).and_wrap_original do |original, *args, &block|
            insert_reference.call
            original.call(*args, &block)
          end
          returned = Places::DeleteIfOrphanJob.new.perform(place.id)
          result = { 'result' => returned, 'place_exists' => Place.exists?(place.id),
                     'active_visit_place_id' => Visit.find(48_601).place_id }
        else
          allow(connection).to receive(:exec_query).and_wrap_original do |original, *args, **kwargs|
            selected = original.call(*args, **kwargs)
            insert_reference.call if args[1] == 'OrphanCleanup victims' && selected.rows.any?
            selected
          end
          Places::OrphanCleanupJob.new.perform(user.id)
          result = { 'deleted_count' => Place.exists?(place.id) ? 0 : 1, 'place_exists' => Place.exists?(place.id),
                     'active_visit_place_id' => Visit.find(48_601).place_id }
        end
      end
    end
    result
  ensure
    Visit.where(id: 48_601, user_id: USER_ID).delete_all
    Place.where(id: PLACE_ID, user_id: USER_ID).delete_all
    User.unscoped.where(id: USER_ID, email: "a12d2-#{USER_ID}@example.invalid").delete_all
    source_restore_sequences(connection, sequences)
    clear_enqueued_jobs
    PhoenixSchema.reset!
  end
end
