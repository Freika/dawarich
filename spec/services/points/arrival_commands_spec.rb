# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::ArrivalCommands do
  let(:user) { create(:user) }
  let(:rows) { [{ 'id' => 1, 'timestamp' => 5, 'longitude' => 13.4, 'latitude' => 52.5 }] }
  let(:payloads) do
    {
      'points.tile_epoch' => { 'timestamps' => [1_704_110_400, 1_790_000_000] },
      'points.anomaly_filter' => { 'start_at' => 10, 'end_at' => 20 },
      'tracks.realtime' => {},
      'tracks.backfill' => { 'timestamps' => [1_704_110_400, 1_704_110_500] },
      'visits.realtime' => {},
      'points.live_broadcast' => { 'broadcast_id' => 'b-1', 'upserted' => rows,
                                    'payloads' => [{ 'timestamp' => 5, 'battery' => 80 }] }
    }
  end
  let(:producers) { [Tracks::RealtimeDebouncer, Tracks::BackfillScheduler, Visits::RealtimeDebouncer, Points::LiveBroadcaster] }

  def run(kind, payload = payloads.fetch(kind), user_id: user.id)
    RailsCommands::Registry.handler(kind).call(payload.merge('user_id' => user_id))
  end

  def redis_keys = Sidekiq.redis { |r| r.keys('*') }.sort

  def geocoding(enabled)
    allow(Geocoding::Config).to receive(:for).and_return(instance_double(Geocoding::Config, enabled?: enabled))
  end

  before { Sidekiq.redis(&:flushdb) }

  it 'bumps the tile epoch with the slice timestamps' do
    allow(Points::TileEpoch).to receive(:bump)
    run('points.tile_epoch')
    expect(Points::TileEpoch).to have_received(:bump).with(user.id, timestamps: [1_704_110_400, 1_790_000_000])
  end

  it 'enqueues the anomaly filter over the batch range on the points queue' do
    expect do
      run('points.anomaly_filter')
    end.to have_enqueued_job(Points::AnomalyFilterJob).with(user.id, 10, 20).on_queue('points')
  end

  it 'triggers the realtime track debouncer once for two deliveries' do
    expect { 2.times { run('tracks.realtime') } }.to have_enqueued_job(Tracks::RealtimeGenerationJob).with(user.id).exactly(:once)
  end

  it 'schedules one backfill for two deliveries of old timestamps' do
    expect { 2.times { run('tracks.backfill') } }.to have_enqueued_job(Tracks::BackfillGenerationJob).with(user.id).exactly(:once)
  end

  it 'schedules one visit suggestion, with ISO bounds in the user time zone, for two deliveries' do
    user.update_columns(settings: user.settings.merge('timezone' => 'Asia/Tokyo',
                                                      'visits_suggestions_enabled' => 'true'))
    geocoding(true)

    expect { 2.times { run('visits.realtime') } }.to have_enqueued_job(VisitSuggestingJob).exactly(:once)
    args = enqueued_jobs.find { _1[:job] == VisitSuggestingJob }[:args].first
    expect([args['start_at'], args['end_at']]).to all(end_with('+09:00'))
  end

  it 'schedules no visit suggestion when geocoding is disabled, and none when the user has not opted in' do
    user.update_columns(settings: user.settings.merge('visits_suggestions_enabled' => 'true'))
    geocoding(false)
    expect { run('visits.realtime') }.not_to have_enqueued_job(VisitSuggestingJob)

    user.update_columns(settings: user.settings.merge('visits_suggestions_enabled' => 'false'))
    geocoding(true)
    expect { run('visits.realtime') }.not_to have_enqueued_job(VisitSuggestingJob)
  end

  it 'broadcasts the rows with symbolized payloads, in the user time zone' do
    user.update_columns(settings: user.settings.merge('timezone' => 'Asia/Tokyo'))
    zones = []
    allow(Points::LiveBroadcaster).to receive(:new).and_wrap_original do |original, *args|
      zones << Time.zone.name
      original.call(*args)
    end
    run('points.live_broadcast')

    expect(Points::LiveBroadcaster).to have_received(:new).with(user.id, rows, [{ timestamp: 5, battery: 80 }])
    expect(zones).to eq(['Asia/Tokyo'])
  end

  it 'broadcasts at most once per broadcast_id: the marker lives a day and a repeat skips' do
    allow(Points::LiveBroadcaster).to receive(:new).and_return(instance_double(Points::LiveBroadcaster, call: nil))
    2.times { run('points.live_broadcast') }

    expect(Points::LiveBroadcaster).to have_received(:new).once
    expect(Sidekiq.redis { |r| r.ttl('live_broadcast:done:b-1') }).to be_within(5).of(86_400)
  end

  it 'claims the live broadcast marker row once' do
    phoenix_state!
    allow(Points::LiveBroadcaster).to receive(:new).and_return(instance_double(Points::LiveBroadcaster, call: nil))
    2.times { run('points.live_broadcast') }

    expect(Points::LiveBroadcaster).to have_received(:new).once
    seconds = ActiveRecord::Base.connection.select_value(
      'SELECT extract(epoch FROM expires_at - statement_timestamp()) FROM phoenix.once_claims ' \
      "WHERE key = 'live_broadcast:done:b-1'"
    ).to_f
    expect(seconds).to be_between(86_399, 86_400)
    expect(Sidekiq.redis { |r| r.exists('live_broadcast:done:b-1') }).to eq(0)
  end

  it 'keeps the marker when the broadcast raises, so the retry does not broadcast again' do
    broadcaster = instance_double(Points::LiveBroadcaster)
    allow(broadcaster).to receive(:call).and_raise(RuntimeError, 'cable down')
    allow(Points::LiveBroadcaster).to receive(:new).and_return(broadcaster)

    expect { run('points.live_broadcast') }.to raise_error(RuntimeError, 'cable down')
    run('points.live_broadcast')
    expect(broadcaster).to have_received(:call).once
  end

  it 'skips every kind for a missing or soft-deleted user without calling a producer' do
    deleted = create(:user).tap { _1.update_columns(deleted_at: Time.current) }
    allow(Points::TileEpoch).to receive(:bump)
    allow(Points::AnomalyFilterJob).to receive(:perform_later)
    producers.each { allow(_1).to receive(:new) }

    payloads.each_key { |kind| [0, deleted.id].each { |id| expect(run(kind, user_id: id)).to be_nil } }

    expect(Points::TileEpoch).not_to have_received(:bump)
    expect(Points::AnomalyFilterJob).not_to have_received(:perform_later)
    producers.each { expect(_1).not_to have_received(:new) }
    expect(redis_keys).to be_empty
  end

  it 'raises KeyError for a payload without a required key, for every kind, before looking up the user' do
    { 'points.tile_epoch' => 'timestamps', 'points.anomaly_filter' => 'end_at', 'tracks.backfill' => 'timestamps',
      'points.live_broadcast' => 'broadcast_id' }.each do |kind, key|
      expect { run(kind, payloads.fetch(kind).except(key), user_id: 0) }.to raise_error(KeyError, /#{key}/)
    end
    payloads.each_key do |kind|
      expect { RailsCommands::Registry.handler(kind).call(payloads.fetch(kind)) }.to raise_error(KeyError, /user_id/)
    end
  end
end
