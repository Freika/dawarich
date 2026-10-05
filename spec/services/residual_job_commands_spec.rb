# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Residual job commands' do
  it 'route hand-back does not change job authority or activate deferred job families' do
    user = create(:user)
    place = create(:place, user: user)
    family = create(:family)
    due = 1.hour.from_now.change(usec: 0)
    cycle = SecureRandom.uuid
    walk = SecureRandom.uuid
    walk_arguments = [user.id, nil, { walk_id: walk, time_zone: 'UTC' }]
    commands = {
      'tracks.backfill' => [{ 'user_id' => user.id, 'cycle_id' => cycle, 'time_zone' => 'UTC' },
                            Tracks::BackfillGenerationJob, [user.id, { cycle_id: cycle, time_zone: 'UTC' }]],
      'tracks.throttled_backfill' => [{ 'user_id' => user.id, 'walk_id' => walk, 'cursor_timestamp' => nil,
                                      'time_zone' => 'UTC' },
                                      Tracks::ThrottledBackfillJob, walk_arguments],
      'families.auto_create' => [{ 'user_id' => user.id, 'time_zone' => 'UTC' }, Families::AutoCreationJob, [user.id]],
      'families.member_sync' => [{ 'family_id' => family.id, 'locale' => 'de', 'time_zone' => 'UTC' },
                                 Families::MemberSyncJob, [family.id]],
      'places.name_fetch' => [{ 'user_id' => user.id, 'place_id' => place.id }, Places::NameFetchingJob, [place.id]],
      'places.delete_if_orphan' => [{ 'user_id' => user.id, 'place_id' => place.id }, Places::DeleteIfOrphanJob,
                                    [place.id]],
      'places.orphan_cleanup' => [{ 'user_id' => user.id }, Places::OrphanCleanupJob, [user.id]],
      'places.bulk_name_fetch' => [{}, Places::BulkNameFetchingJob, []],
      'achievements.bulk_check' => [{ 'notify' => false, 'force' => true, 'stale_only' => true },
                                    Achievements::BulkCheckJob, [{ notify: false, force: true, stale_only: true }]]
    }
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))
    %w[airtrail_flight_import_job teslamate_sync_job trek_sync_job achievements_bulk_check_job].each do |key|
      config = schedule.fetch(key)
      klass = config.fetch('class').constantize
      serialized = klass.new(*config.fetch('args')).serialize
      job_owner!("cron:#{key}", :oban)
      decoded = ActiveJob::Base.deserialize(serialized)
      decoded.perform_now
      expect(decoded.arguments).to eq(['a12d2_cron'])
      expect(serialized.fetch('queue_name')).to eq(config.fetch('queue'))
    end
    before = ENV.to_h.slice('DAWARICH_RAILS_ROUTES', 'DAWARICH_RAILS_SLICES')
    begin
      ENV['DAWARICH_RAILS_ROUTES'] = '/api/v1/places,/api/v1/families,/api/v1/tracks'
      ENV['DAWARICH_RAILS_SLICES'] = 'api_places,api_family,api_map_reads'
      JobOutbox.delete_all
      clear_enqueued_jobs
      commands.each do |type, (payload, _klass, _args)|
        job_owner!("command:#{type}", :oban)
        expect(JobCommands.produce(type, payload, aggregate_id: user.id, producer: 'a12d2-spec', scheduled_at: due))
          .to eq(:outbox)
      end
      expect(JobOutbox.pending.count).to eq(9)
      expect(enqueued_jobs).to be_empty
      commands.each do |type, (_payload, klass, arguments)|
        JobCommands.rehome!(type, by: 'a12d2-spec')
        expect(klass).to have_been_enqueued.with(*arguments).at(due)
      end
      expect(JobOutbox.pending.count).to eq(0)
      deferred = %w[visits.bulk_suggest pending_imports.cleanup release.achievements_bulk_check teslamate.sync
                    trek.sync]
      expect(JobCommands::COMMANDS.keys & deferred).to be_empty
    ensure
      %w[DAWARICH_RAILS_ROUTES DAWARICH_RAILS_SLICES].each do |key|
        before.key?(key) ? ENV[key] = before[key] : ENV.delete(key)
      end
    end
  end
end

RSpec.describe 'Residual native handoff', :eval do
  include ActiveSupport::Testing::TimeHelpers
  self.use_transactional_tests = false

  def handoff_sql(statement, *values)
    rows = ActiveRecord::Base.connection.exec_query(ActiveRecord::Base.sanitize_sql_array([statement, *values])).to_a
    rows.each { |row| row['payload'] = JSON.parse(row['payload']) if row['payload'].is_a?(String) }
    rows
  end

  def handoff_sequences
    %w[public.users_id_seq public.points_id_seq public.trip_sources_id_seq
       phoenix.rails_commands_id_seq].index_with do |sequence|
      handoff_sql("SELECT last_value,is_called FROM #{sequence}").sole
    end
  end

  def clean_handoff(ids, events, sequences)
    handoff_sql("DELETE FROM phoenix.rails_commands WHERE (payload->>'user_id')::bigint IN (?)", ids)
    handoff_sql('DELETE FROM phoenix.processed_commands WHERE event_id IN (?)', events) unless events.empty?
    JobOutbox.where("payload->>'user_id' IN (?)", ids.map(&:to_s)).delete_all
    TripSource.where(user_id: ids).delete_all
    Point.where(user_id: ids).delete_all
    User.unscoped.where(id: ids).delete_all
    sequences.each do |sequence, state|
      next if handoff_sql("SELECT last_value,is_called FROM #{sequence}").sole == state

      handoff_sql('SELECT setval(?, ?, ?)', sequence, state.fetch('last_value'), state.fetch('is_called'))
    end
    PhoenixSchema.reset!
  end

  it 'adopts actual native bootstrap legacy backoff and queued cursor without shortening TTL' do
    expect(ActiveRecord::Base.connection_db_config.database).to eq('dawarich_phoenix_test_a12d2_scratch')
    ids = [49_501, 49_502]
    events = []
    sequences = handoff_sequences
    keys = %w[command:tracks.throttled_backfill command:tracks.generate_range]
    owners = handoff_sql('SELECT * FROM phoenix.job_owners WHERE key IN (?)', keys)
    rows = handoff_sql('SELECT id,kind,payload FROM phoenix.rails_commands WHERE ' \
                       "(payload->>'user_id')::bigint IN (?) ORDER BY id", ids)
    expect(rows.map { _1.fetch('payload').fetch('user_id') }).to eq(ids)
    now = Time.utc(2026, 10, 4, 12)
    travel_to now do
      rows.each { RailsCommands::Poller.deliver(_1.fetch('id')) }
      walks = handoff_sql('SELECT * FROM phoenix.track_backfill_walks WHERE user_id IN (?) ORDER BY user_id', ids)
      expect(walks.map { _1.fetch('state') }).to eq(%w[backoff backoff])
      expect(walks.map { _1.fetch('cursor_timestamp') }).to eq([nil, nil])
      expect(walks.first.fetch('expires_at')).to be_between(now + 6.days - 60, now + 6.days)
      expect(walks.last.fetch('expires_at')).to be_between(now + 10.hours - 60, now + 10.hours)
      expect(JobOutbox.where(aggregate_id: ids)).to be_empty
      Point.insert_all!([{ id: 49_502, user_id: 49_502, timestamp: 50, lonlat: 'POINT(1 1)',
                          created_at: now, updated_at: now }])
      legacy = Tracks::ThrottledBackfillJob.new(49_502, 100, time_zone: 'Europe/Berlin')
      events << legacy.job_id
      legacy.perform_now
      selected = handoff_sql('SELECT * FROM phoenix.track_backfill_walks WHERE user_id = 49502').sole
      expect(selected).to include('state' => 'walking', 'cursor_timestamp' => 100,
                                  'selected_end_timestamp' => nil)
      expect(JobOutbox.where(aggregate_id: ids).sole.payload).to eq(
        selected.slice('user_id', 'walk_id', 'cursor_timestamp', 'time_zone')
      )
      expect(selected.fetch('expires_at')).to eq(walks.last.fetch('expires_at'))
      expect(handoff_sql('SELECT * FROM phoenix.track_backfill_walks WHERE user_id = 49501').sole).to eq(walks.first)
      expect(Sidekiq.redis { _1.exists(*ids.map { |id| Tracks::ThrottledBackfillJob.redis_key(id) }) }).to eq(0)
    end
  ensure
    if sequences
      handoff_sql('DELETE FROM phoenix.track_backfill_walks WHERE user_id IN (?)', ids)
      clean_handoff(ids, events, sequences)
      handoff_sql('DELETE FROM phoenix.job_owners WHERE key IN (?)', keys)
      owners.each do |owner|
        connection = ActiveRecord::Base.connection
        connection.execute("INSERT INTO phoenix.job_owners (#{owner.keys.join(',')}) VALUES " \
                           "(#{owner.values.map { connection.quote(_1) }.join(',')})")
      end
      Sidekiq.redis { _1.del(*ids.map { |id| Tracks::ThrottledBackfillJob.redis_key(id) }) }
    end
  end

  it 'consumes actual native reverse rows through the registered handlers' do
    expect(ActiveRecord::Base.connection_db_config.database).to eq('dawarich_phoenix_test_a12d2_scratch')
    sequences = handoff_sequences
    ids = [48_801, 48_802]
    cycles = %w[00000000-0000-4000-8000-000000048801 00000000-0000-4000-8000-000000048802]
    events = cycles + ids.flat_map do |id|
      %w[airtrail teslamate trek].map do |provider|
        row_id = provider == 'trek' ? id + 20 : id
        Integrations::SchedulingCommands.event_id("#{provider}.scheduled", 1_791_115_200, row_id)
      end
    end
    actual = handoff_sql(
      "SELECT kind,payload FROM phoenix.rails_commands WHERE (payload->>'user_id')::bigint IN (?) ORDER BY id", ids
    )
    expect(actual.size).to eq(8)
    expect(User.where(id: ids).count).to eq(2)
    expect(handoff_sql('SELECT event_id FROM phoenix.processed_commands WHERE event_id IN (?)', cycles).size).to eq(2)
    expected = {
      'integrations.airtrail_flights' => AirTrail::ImportFlightsJob,
      'integrations.teslamate_sync' => TeslaMate::SyncJob,
      'integrations.trek_sync' => Trek::SyncJob,
      'tracks_generate_range' => Tracks::ParallelGeneratorJob
    }
    expect(actual.group_by { _1.fetch('kind') }.transform_values(&:size)).to eq(expected.transform_values { 2 })
    clear_enqueued_jobs
    actual.each do |row|
      kind = row.fetch('kind')
      payload = row.fetch('payload')
      user_id = payload.fetch('user_id')
      if kind.start_with?('integrations.')
        provider = kind.split('.').last.split('_').first
        row_id = provider == 'trek' ? user_id + 20 : user_id
        expect(payload.fetch('event_id')).to eq(Integrations::SchedulingCommands.event_id(provider, 1_791_115_200,
                                                                                          row_id))
      end
      handler = RailsCommands::Registry.handler(kind)
      expect(handler).to be_present
      2.times { handler.call(payload) }
      klass = expected.fetch(kind)
      if kind == 'tracks_generate_range'
        zone = ActiveSupport::TimeZone['Europe/Berlin']
        options = { start_at: zone.local(2026, 10, 3), end_at: zone.local(2026, 10, 4, 8),
                    mode: :bulk, untracked_only: true, import_id: nil, job_queue: nil }
        expect(Tracks::GenerationCommand.job_options(payload)).to eq(options)
        expect(klass).to have_been_enqueued.with(user_id, **options).twice.on_queue('tracks').at(:no_wait)
      else
        argument = payload['source_id'] || user_id
        expect(payload.fetch('source_id')).to eq(user_id + 20) if kind == 'integrations.trek_sync'
        expect(klass).to have_been_enqueued.with(argument).twice.on_queue('imports').at(:no_wait)
      end
    end
    expect(enqueued_jobs.size).to eq(16)
    mismatched = actual.find { _1['kind'] == 'integrations.trek_sync' }.fetch('payload').merge('user_id' => 48_802)
    mismatched['source_id'] = 48_821
    expect { RailsCommands::Registry.handler('integrations.trek_sync').call(mismatched) }
      .not_to(change { enqueued_jobs.size })
  ensure
    clean_handoff(ids, events, sequences) if sequences
  end

  it 'same-slot Rails and native crons sweep once for all four exact owner keys' do
    expect(ActiveRecord::Base.connection_db_config.database).to eq('dawarich_phoenix_test_a12d2_scratch')
    sequences = handoff_sequences
    groups = { 'airtrail_flight_import_job' => [51_001, 52_001, AirTrail::ImportFlightsJob, 'airtrail'],
               'teslamate_sync_job' => [53_001, 54_001, TeslaMate::SyncJob, 'teslamate'],
               'trek_sync_job' => [55_001, 56_001, Trek::SyncJob, 'trek'],
               'achievements_bulk_check_job' => [57_001, 57_201, Achievements::CheckJob, nil] }
    ids = groups.values.flat_map { |first, last, _klass, _provider| (first..last).to_a }
    slot = 1_791_115_200
    root = Achievements::BulkCommands.root(nil, slot)
    events = groups.values.flat_map do |first, last, _leaf, provider|
      (first..last).map do |id|
        if provider
          Integrations::SchedulingCommands.event_id("#{provider}.scheduled", slot, id)
        else
          Digest::UUID.uuid_v5(root, "scheduled:#{id}")
        end
      end
    end
    events << root
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))
    actual = handoff_sql("SELECT kind,payload FROM phoenix.rails_commands WHERE (payload->>'user_id')::bigint IN (?)",
                         ids)
    expect(actual.size).to eq(3200)
    expect(User.where(id: ids).count).to eq(3204)
    travel_to Time.utc(2026, 10, 4, 12) do
      groups.each do |key, (first, last, leaf, provider)|
        native = actual.select { _1.fetch('payload').fetch('user_id').between?(first, last) }
        expect(native.size).to eq(provider ? 1000 : 200)
        native_ids = native.map { _1.fetch('payload').fetch('user_id') }
        remaining = ((first..last).to_a - native_ids).sole
        root = Achievements::BulkCommands.root(nil, slot)
        receipts = (first..last).map do |id|
          if provider
            Integrations::SchedulingCommands.event_id("#{provider}.scheduled", slot, id)
          else
            Digest::UUID.uuid_v5(root, "scheduled:#{id}")
          end
        end
        expect(handoff_sql('SELECT event_id FROM phoenix.processed_commands WHERE event_id IN (?)', receipts).size)
          .to eq(provider ? 1000 : 200)
        config = schedule.fetch(key)
        klass = config.fetch('class').constantize
        serialized = klass.new(*config.fetch('args')).serialize
        invoke = lambda {
          job = ActiveJob::Base.deserialize(serialized)
          job.enqueued_at = Time.current
          job.perform_now
          expect(job.arguments).to eq(['a12d2_cron'])
        }
        clear_enqueued_jobs
        job_owner!("cron:#{key}", :oban)
        job_owner!('command:achievements.bulk_check', :oban) unless provider
        invoke.call
        expect(enqueued_jobs).to be_empty
        expect(JobOutbox.pending.count).to eq(0)
        job_owner!('command:achievements.bulk_check', :sidekiq) unless provider
        job_owner!("cron:#{key}", :sidekiq)
        invoke.call
        if provider
          expect(leaf).to have_been_enqueued.with(remaining).once
        else
          expect(leaf).to have_been_enqueued.with(remaining, notify: true, force: false).once
        end
        expect(enqueued_jobs.size).to eq(1)
        expect(handoff_sql('SELECT event_id FROM phoenix.processed_commands WHERE event_id IN (?)', receipts).size)
          .to eq(provider ? 1001 : 201)
        handoff_sql('DELETE FROM phoenix.job_owners WHERE key=?', "cron:#{key}")
        clear_enqueued_jobs
        invoke.call
        expect(enqueued_jobs).to be_empty
        expect(JobOutbox.pending.count).to eq(0)
      end
    end
  ensure
    if sequences
      clean_handoff(ids, events, sequences)
      groups.each_key { handoff_sql('DELETE FROM phoenix.job_owners WHERE key=?', "cron:#{_1}") }
      JobOutbox.where(event_id: Achievements::BulkCommands.root(nil, slot)).delete_all
      handoff_sql("DELETE FROM phoenix.job_owners WHERE key='command:achievements.bulk_check'")
    end
  end
end
