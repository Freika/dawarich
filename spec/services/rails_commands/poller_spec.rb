# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe RailsCommands::Poller do
  let(:user) { create(:user) }

  after do
    described_class.stop
    poller_threads.each do |thread|
      thread.kill
      thread.join
    end
    expect(poller_threads).to be_empty
  end

  def sql(text, *binds) = ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([text, *binds]))

  def command!(kind, payload, attempts: 0, available_at: 'now()', leased_until: 'NULL')
    sql(<<~SQL.squish, kind, payload.to_json, attempts).first['id']
      INSERT INTO phoenix.rails_commands (kind, payload, attempts, available_at, leased_until)
      VALUES (?, ?::jsonb, ?, #{available_at}, #{leased_until}) RETURNING id
    SQL
  end

  def commands = sql('SELECT * FROM phoenix.rails_commands ORDER BY id').to_a
  def dead = sql('SELECT * FROM phoenix.rails_commands_dead ORDER BY id').to_a

  def expire_leases!
    sql("UPDATE phoenix.rails_commands SET leased_until = now() - interval '1 second' WHERE leased_until IS NOT NULL")
  end

  def make_due! = sql('UPDATE phoenix.rails_commands SET available_at = now()')
  def month_key(user) = Timeline::MonthSummary.cache_key_for(user, Date.new(2026, 6, 1))
  def months(user) = { 'user_id' => user.id, 'started_at' => ['2026-06-15T10:00:00Z'] }
  def stub_bust = allow(Visits::Detection::MachineVisitWipe).to receive(:bust_month_caches)
  def poller_threads = Thread.list.select { _1.name == described_class::THREAD_NAME }

  it 'does nothing before Phoenix ever migrated' do
    expect(described_class.drain_once).to eq(0)

    phoenix_tables!

    connection = ActiveRecord::Base.connection
    expect(connection.select_value("SELECT to_regclass('phoenix.rails_commands')")).not_to be_nil
    expect(connection.select_value("SELECT to_regclass('phoenix.rails_commands_dead')")).not_to be_nil
    expect(described_class.drain_once).to eq(0)
  end

  it 'visit_months_changed busts the named timeline month caches and deletes its row' do
    phoenix_tables!
    Rails.cache.write(month_key(user), 'x')
    command!('visit_months_changed', months(user))

    expect(described_class.drain_once).to eq(1)
    expect(Rails.cache.read(month_key(user))).to be_nil
    expect(commands).to be_empty
    expect(dead).to be_empty
  end

  it 'the claim leases the oldest due row for 60 s and counts the attempt' do
    phoenix_tables!
    id = command!('visit_months_changed', months(user))
    command!('visit_months_changed', months(create(:user)))

    expect(described_class.claim).to include('id' => id, 'attempts' => 1, 'lease' => be_present)
    row = commands.first
    expect(row['leased_until']).to be_within(2.seconds).of(60.seconds.from_now)
    expect(row['attempts']).to eq(1)
  end

  it 'a crash after the claim retries the row once the lease expires' do
    phoenix_tables!
    stub_bust
    command!('visit_months_changed', months(user))
    described_class.claim

    expect(described_class.drain_once).to eq(0)
    expect(Visits::Detection::MachineVisitWipe).not_to have_received(:bust_month_caches)

    expire_leases!

    expect(described_class.drain_once).to eq(1)
    expect(Visits::Detection::MachineVisitWipe).to have_received(:bust_month_caches).once
    expect(commands).to be_empty
    expect(dead).to be_empty
  end

  it 'a slow producer does not double-run within its lease, and a late finish deletes nothing' do
    phoenix_tables!
    old = command!('visit_months_changed', months(user)).then { described_class.claim }

    expect(described_class.claim).to be_nil

    expire_leases!
    new = described_class.claim
    expect(new).to include('id' => old['id'], 'attempts' => 2)
    sql("UPDATE phoenix.rails_commands SET leased_until = now() + interval '2 minutes' WHERE id = #{new['id']}")
    new['lease'] =
      sql("SELECT leased_until::text AS lease FROM phoenix.rails_commands WHERE id = #{new['id']}").first['lease']

    allow(Rails.logger).to receive(:warn)
    described_class.complete(old)
    expect(commands).not_to be_empty
    expect(Rails.logger).to have_received(:warn)
      .with("[RailsCommands] #{old['id']} (visit_months_changed) finished after its lease passed on; nothing settled")

    described_class.complete(new)
    expect(commands).to be_empty
  end

  it 'success deletes only the leased row' do
    phoenix_tables!
    command!('visit_months_changed', months(user))
    command!('visit_months_changed', months(create(:user)))
    first = described_class.claim
    second = described_class.claim
    sql("UPDATE phoenix.rails_commands SET leased_until = now() + interval '2 minutes' WHERE id = #{second['id']}")

    described_class.complete(first)
    described_class.complete(second)
    described_class.fail_attempt(second, RuntimeError.new('cache down'))

    expect(commands.map { _1['id'] }).to eq([second['id']])
    expect(commands.first['leased_until']).to be_present
  end

  it 'a raising producer backs off and then succeeds' do
    phoenix_tables!
    stub_bust.and_invoke(->(*) { raise 'cache down' }, ->(*) {})
    id = command!('visit_months_changed', months(user))

    expect(described_class.drain_once).to eq(1)
    row = commands.first
    expect(row).to include('id' => id, 'attempts' => 1, 'leased_until' => nil)
    expect(JSON.parse(row['payload'])).to eq(months(user))
    expect(row['available_at']).to be_within(2.seconds).of(16.seconds.from_now)
    expect(described_class.drain_once).to eq(0)

    make_due!

    expect(described_class.drain_once).to eq(1)
    expect(commands).to be_empty
    expect(dead).to be_empty
    expect(Visits::Detection::MachineVisitWipe).to have_received(:bust_month_caches).twice
  end

  it 'the 25th failing attempt moves the row to dead atomically and logs at error level' do
    phoenix_tables!
    stub_bust.and_raise(RuntimeError, 'cache down')
    id = command!('visit_months_changed', months(user), attempts: 24)
    expect(Rails.logger).to receive(:error).with(/#{id} \(visit_months_changed\) dead after 25 attempts: RuntimeError/)

    expect(described_class.drain_once).to eq(1)
    expect(commands).to be_empty
    expect(dead).to include(a_hash_including('id' => id, 'kind' => 'visit_months_changed', 'attempts' => 25,
                                             'last_error' => 'RuntimeError: cache down'))
    expect(JSON.parse(dead.first['payload'])).to eq(months(user))
  end

  it 'a row whose leases expired 25 times goes to dead without running' do
    phoenix_tables!
    stub_bust
    command!('visit_months_changed', months(user), attempts: 25, leased_until: "now() - interval '1 second'")

    expect(described_class.drain_once).to eq(1)
    expect(Visits::Detection::MachineVisitWipe).not_to have_received(:bust_month_caches)
    expect(dead.first).to include('attempts' => 25, 'last_error' => a_string_starting_with('RailsCommands::Poller::LeaseExpired'))
  end

  it 'a bury that lost its lease moves nothing and logs no death' do
    phoenix_tables!
    command!('visit_months_changed', months(user))
    stale = described_class.claim
    expire_leases!
    described_class.claim
    sql("UPDATE phoenix.rails_commands SET leased_until = now() + interval '2 minutes'")
    allow(Rails.logger).to receive(:warn)
    expect(Rails.logger).not_to receive(:error)

    described_class.bury(stale, 25, RuntimeError.new('cache down'))

    expect(dead).to be_empty
    expect(commands.sole['attempts']).to eq(2)
    expect(Rails.logger).to have_received(:warn)
      .with("[RailsCommands] #{stale['id']} (visit_months_changed) failed after its lease passed on; nothing settled")
  end

  it 'a non-database error in one batch is logged and the next batch still runs' do
    phoenix_tables!
    command!('visit_months_changed', months(user))
    allow(described_class).to receive(:sleep)
    calls = 0
    allow(ActiveRecord::Base.connection).to receive(:exec_query).and_wrap_original do |method, *args, **options|
      calls += 1
      raise IOError, 'socket closed' if calls == 1

      method.call(*args, **options)
    end
    expect(Rails.logger).to receive(:warn).with('[RailsCommands] poll: IOError')

    expect { described_class.drain_safely }.not_to raise_error
    described_class.drain_safely

    expect(commands).to be_empty
  end

  it 'a settle statement that fails leaves the row to its lease and loses nothing' do
    phoenix_tables!
    stub_bust
    command!('visit_months_changed', months(user))
    allow(described_class).to receive(:complete).and_raise(ActiveRecord::StatementInvalid, 'db down')
    expect(Rails.logger).to receive(:warn).with(/not settled: ActiveRecord::StatementInvalid/)

    expect(described_class.drain_once).to eq(1)
    expect(commands.first['leased_until']).to be_present

    allow(described_class).to receive(:complete).and_call_original
    expire_leases!

    expect(described_class.drain_once).to eq(1)
    expect(commands).to be_empty
  end

  it 'no row is lost: every claimed row ends deleted, backed off or dead' do
    phoenix_tables!
    users = create_list(:user, 10)
    ids = users.each_with_index.map do |candidate, index|
      command!('visit_months_changed', months(candidate), attempts: index.zero? ? 24 : 0)
    end
    ids << command!('visit_months_changed', { 'user_id' => 0, 'started_at' => ['2026-06-15T10:00:00Z'] })
    failing = users.first(5)
    stub_bust.and_wrap_original do |method, candidate, times|
      raise 'cache down' if failing.include?(candidate)

      method.call(candidate, times)
    end

    expect(described_class.drain_once).to eq(11)
    expect(dead.map { _1['id'] }).to eq([ids.first])
    expect(commands.map { _1['id'] }).to eq(ids[1..4])
    expect(commands).to all(include('attempts' => 1, 'leased_until' => nil))
    users.last(5).each do |candidate|
      expect(Visits::Detection::MachineVisitWipe).to have_received(:bust_month_caches).with(candidate, kind_of(Array))
    end
  end

  it 'a slow row leases only itself, so another poller never runs the rows behind it twice' do
    phoenix_tables!
    users = create_list(:user, 3)
    users.each { command!('visit_months_changed', months(_1)) }
    runs = Hash.new(0)
    taken_over = nil
    stub_bust.and_wrap_original do |_method, candidate, _times|
      runs[candidate.id] += 1
      next unless candidate == users[1] && runs[candidate.id] == 1

      expire_leases!
      taken_over = described_class.drain_once
    end

    described_class.drain_once

    expect(taken_over).to eq(2)
    expect(runs.values_at(*users.map(&:id))).to eq([1, 2, 1])
    expect(commands).to be_empty
    expect(dead).to be_empty
  end

  it 'a poller killed mid-batch costs the rows it had not started no attempt' do
    phoenix_tables!
    users = create_list(:user, 3)
    ids = users.map { command!('visit_months_changed', months(_1)) }
    sql("UPDATE phoenix.rails_commands SET attempts = 24 WHERE id = #{ids.last}")
    killed = Class.new(Exception) # rubocop:disable Lint/InheritException
    stub_bust.and_invoke(->(*) {}, ->(*) { raise killed }, ->(*) {}, ->(*) {})

    expect { described_class.drain_once }.to raise_error(killed)
    expect(commands.map { _1.slice('id', 'attempts', 'leased_until') })
      .to match([include('id' => ids[1], 'attempts' => 1, 'leased_until' => be_present),
                 { 'id' => ids[2], 'attempts' => 24, 'leased_until' => nil }])

    expire_leases!

    expect(described_class.drain_once).to eq(2)
    expect(commands).to be_empty
    expect(dead).to be_empty
  end

  it 'an unknown kind backs off like a failure' do
    phoenix_tables!
    command!('later_kind', { 'user_id' => user.id })
    expect(Rails.logger).to receive(:warn).with(/failed attempt 1: RailsCommands::Poller::UnknownKind/)

    expect(described_class.drain_once).to eq(1)
    expect(commands.first).to include('attempts' => 1, 'leased_until' => nil)
  end

  it 'the claim skips future and leased rows' do
    phoenix_tables!
    command!('visit_months_changed', months(user), available_at: "now() + interval '1 hour'")
    command!('visit_months_changed', months(create(:user)), leased_until: "now() + interval '1 minute'")

    expect(described_class.drain_once).to eq(0)
  end

  it 'backoff follows attempts⁴ + 15 seconds' do
    expect([1, 2, 24].map { described_class.backoff_seconds(_1) }).to eq([16, 31, 331_791])
  end

  it 'rows run in id order within a batch' do
    phoenix_tables!
    users = create_list(:user, 3)
    users.each { command!('visit_months_changed', months(_1)) }
    stub_bust

    described_class.drain_once

    users.each { expect(Visits::Detection::MachineVisitWipe).to have_received(:bust_month_caches).with(_1, kind_of(Array)).ordered }
  end

  it 'every registered kind declares a repeat guard and a callable' do
    expected_kinds = %w[
      visit_months_changed airtrail_stats tracks_changed tracks_generate_range tracks_throttled_backfill
      tracks_realtime_retrigger geocode_recent_points transport_progress schedule_untracked_tracks
      enhanced_import_card places_delete_if_orphan place_name_fetch reverse_geocode_place imports.progress
      exports.points_created family_location_request_mail release_reclassify_tracks release_user_redetect
      release_null_island_follow_up
      points.tile_epoch
      points.anomaly_filter tracks.realtime tracks.backfill visits.realtime points.live_broadcast
      points.anomaly_recalculate points.anomaly_stats imports.postprocessing_step imports.upload_created
      imports.prepare_download imports.prepared_download_purge imports.destroy_requested imports.destroy_status
      imports.destroy_callbacks imports.destroy_achievements imports.destroy_stats imports.destroy_complete
      imports.destroy_terminal imports.extraction_requested imports.extraction_destroy_requested
      route_videos.attachment_job visits.web_redetect imports.resume
      stats.calculate_month stats.caches_invalidated
      digests.calculate_month digests.calculate_year digests.email_month digests.email_year
    ]
    expect(RailsCommands::Registry::HANDLERS.keys).to eq(expected_kinds)
    RailsCommands::Registry::HANDLERS.each_value do |handler|
      expect(handler[:guard]).to be_a(String).and be_present
      expect(handler[:call]).to respond_to(:call)
    end
  end

  it 'tracks_changed broadcasts created, updated and destroyed and bumps the epoch' do
    phoenix_tables!
    start_at = Time.zone.parse('2026-03-29 12:00:00 UTC')
    created = create(:track, user:, start_at:, end_at: start_at + 10.minutes)
    updated = create(:track, user:, start_at: start_at + 20.minutes, end_at: start_at + 30.minutes)
    before = Tracks::TileEpoch.etag_component(user.id, start_at.to_i, (start_at + 1.hour).to_i)
    payload = {
      'user_id' => user.id, 'created' => [created.id], 'updated' => [updated.id], 'destroyed' => [999],
      'min_ts' => start_at.to_i, 'max_ts' => (start_at + 1.hour).to_i
    }
    command!('tracks_changed', payload)
    expect(TracksChannel).to receive(:broadcast_to)
      .with(user, hash_including(action: 'created', track: hash_including(id: created.id))).once
    expect(TracksChannel).to receive(:broadcast_to)
      .with(user, hash_including(action: 'updated', track: hash_including(id: updated.id))).once
    expect(TracksChannel).to receive(:broadcast_to).with(user, hash_including(action: 'destroyed', track_id: 999)).once

    described_class.drain_once

    expect(Tracks::TileEpoch.etag_component(user.id, start_at.to_i, (start_at + 1.hour).to_i)).not_to eq(before)
  end

  it 'tracks_changed with only a range bumps the epoch without broadcasting' do
    phoenix_tables!
    start_at = Time.zone.parse('2026-03-29 12:00:00 UTC')
    before = Tracks::TileEpoch.etag_component(user.id, start_at.to_i, (start_at + 1.hour).to_i)
    payload = {
      'user_id' => user.id, 'created' => [], 'updated' => [], 'destroyed' => [],
      'min_ts' => start_at.to_i, 'max_ts' => (start_at + 1.hour).to_i
    }
    command!('tracks_changed', payload)

    expect { described_class.drain_once }.not_to have_broadcasted_to(user).from_channel(TracksChannel)
    expect(Tracks::TileEpoch.etag_component(user.id, start_at.to_i, (start_at + 1.hour).to_i)).not_to eq(before)
  end

  it 'tracks_generate_range enqueues today’s job' do
    phoenix_tables!
    at = Time.zone.parse('2026-03-29 12:34:56 UTC')
    payload = Tracks::GenerationCommand.payload(user.id, start_at: at, end_at: at + 1.hour, mode: :daily,
                                                 untracked_only: false, import_id: nil, job_queue: nil)
    command!('tracks_generate_range', payload)

    expect { described_class.drain_once }.to have_enqueued_job(Tracks::ParallelGeneratorJob)
      .with(user.id, hash_including(mode: :daily))
  end

  it 'tracks_throttled_backfill schedules once' do
    phoenix_tables!
    command!('tracks_throttled_backfill', { 'user_id' => user.id })
    command!('tracks_throttled_backfill', { 'user_id' => user.id })

    expect { described_class.drain_once }.to have_enqueued_job(Tracks::ThrottledBackfillJob).once.with(user.id, nil)
  end

  it 'tracks_realtime_retrigger arms the debouncer' do
    phoenix_tables!
    command!('tracks_realtime_retrigger', { 'user_id' => user.id })

    expect { described_class.drain_once }.to have_enqueued_job(Tracks::RealtimeGenerationJob).with(user.id)
    expect(claim_seconds("track_realtime:user:#{user.id}")).to be_between(119, 120)
  end

  it 'geocode_recent_points uses the payload’s since' do
    phoenix_tables!
    since = Time.zone.parse('2026-03-29 12:00:00 UTC')
    older = create(:point, user:, longitude: 12.37, latitude: 51.34, created_at: since + 3.minutes)
    newer = create(:point, user:, longitude: 12.371, latitude: 51.341, created_at: since + 11.minutes)
    config = instance_double(Geocoding::Config, enabled?: true)
    allow(Geocoding::Config).to receive(:for).with(user.id).and_return(config)
    command!('geocode_recent_points', { 'user_id' => user.id, 'since' => (since + 5.minutes).to_i })

    expect { described_class.drain_once }
      .to have_enqueued_job(ReverseGeocodingJob).with('Point', newer.id, force: false)
    unexpected_job = hash_including(job: ReverseGeocodingJob, args: ['Point', older.id, { force: false }])
    expect(enqueued_jobs).not_to include(unexpected_job)
  end

  it 'transport_progress counts a repeated delivery once' do
    phoenix_tables!
    status = Tracks::TransportationRecalculationStatus.new(user.id)
    status.start(total_tracks: 2)
    payload = { 'user_id' => user.id, 'event_id' => 'e1' }
    command!('transport_progress', payload)
    command!('transport_progress', payload)

    described_class.drain_once

    expect(status.data).to include('processed_tracks' => 1, 'status' => 'processing')
    command!('transport_progress', { 'user_id' => user.id, 'event_id' => 'e2' })
    described_class.drain_once
    expect(status.data['status']).to eq('completed')
  end

  it 'missing users complete without retrying' do
    phoenix_tables!
    command!('tracks_throttled_backfill', { 'user_id' => 0 })
    command!('geocode_recent_points', { 'user_id' => 0, 'since' => Time.current.to_i })

    expect { described_class.drain_once }.not_to have_enqueued_job(Tracks::ThrottledBackfillJob)
    expect(commands).to be_empty
    expect(dead).to be_empty
  end

  it "schedule_untracked_tracks schedules the import's untracked generation" do
    phoenix_tables!
    import = create(:import, user:)
    create(:point, user:, import:, timestamp: 1.hour.ago.to_i)
    create(:point, user:, import:, timestamp: Time.current.to_i)
    command!('schedule_untracked_tracks', { 'user_id' => user.id, 'import_id' => import.id })

    expect { described_class.drain_once }.to have_enqueued_job(Tracks::ParallelGeneratorJob)
      .with(user.id, hash_including(untracked_only: true, import_id: import.id))
  end

  it 'enhanced_import_card broadcasts the card' do
    phoenix_tables!
    import = create(:import, user:)
    command!('enhanced_import_card', { 'user_id' => user.id, 'import_id' => import.id })

    expect { described_class.drain_once }.to have_broadcasted_to("import_#{import.id}_extraction")
  end

  it 'places_delete_if_orphan enqueues one job per place' do
    phoenix_tables!
    command!('places_delete_if_orphan', { 'user_id' => user.id, 'place_ids' => [1, 2] })

    expect { described_class.drain_once }
      .to have_enqueued_job(Places::DeleteIfOrphanJob).exactly(2).times

    expect(enqueued_jobs.select { |job| job[:job] == Places::DeleteIfOrphanJob }.map { |job| job[:args] })
      .to contain_exactly([1], [2])
  end

  it 'place_name_fetch and reverse_geocode_place enqueue their jobs' do
    phoenix_tables!
    command!('place_name_fetch', { 'user_id' => user.id, 'place_id' => 5 })
    command!('reverse_geocode_place', { 'user_id' => user.id, 'place_id' => 7 })

    expect { described_class.drain_once }.to have_enqueued_job(Places::NameFetchingJob).with(5)
    expect(enqueued_jobs).to include(hash_including(job: ReverseGeocodingJob, args: ['place', 7]))
  end

  it 'a missing import is skipped' do
    phoenix_tables!
    command!('schedule_untracked_tracks', { 'user_id' => user.id, 'import_id' => 0 })
    command!('enhanced_import_card', { 'user_id' => user.id, 'import_id' => 0 })

    expect(described_class.drain_once).to eq(2)
    expect(enqueued_jobs).to be_empty
    expect(commands).to be_empty
    expect(dead).to be_empty
  end

  it 'user-scoped kinds skip a missing user' do
    phoenix_tables!
    command!('places_delete_if_orphan', { 'user_id' => 0, 'place_ids' => [1] })
    command!('place_name_fetch', { 'user_id' => 0, 'place_id' => 1 })
    command!('reverse_geocode_place', { 'user_id' => 0, 'place_id' => 1 })

    expect(described_class.drain_once).to eq(3)
    expect(enqueued_jobs).to be_empty
    expect(commands).to be_empty
    expect(dead).to be_empty
  end

  it 'starts one named poller thread even when started twice' do
    entered = Queue.new
    release = Queue.new
    allow(Rails).to receive(:env).and_return('production'.inquiry)
    allow(described_class).to receive(:drain_safely) do
      entered << Thread.current
      release.pop
    end

    described_class.start
    thread = entered.pop
    described_class.start

    expect(poller_threads).to contain_exactly(thread)
  end

  it 'stops its thread and can start it again' do
    entered = Queue.new
    allow(Rails).to receive(:env).and_return('production'.inquiry)
    allow(described_class).to receive(:drain_safely) do
      entered << Thread.current
      Queue.new.pop
    end

    described_class.start
    first_thread = entered.pop
    described_class.stop

    expect(first_thread).not_to be_alive
    expect(poller_threads).to be_empty

    described_class.start
    second_thread = entered.pop

    expect(second_thread).not_to equal(first_thread)
    expect(poller_threads).to contain_exactly(second_thread)
  end
end
