# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEvents::Record do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:place) { create(:place, :geofence, user:) }
  let!(:webhook) { create(:webhook, user:) }

  before { GeofenceEvents::StateStore.new(user).reset! }

  def record(event_type, source: :server_inferred, occurred_at: Time.current, **options)
    described_class.call(user:, place:, event_type:, source:, occurred_at:,
                         lonlat: 'POINT(13.539 52.437)', **options)
  end

  it 'stores an enter and queues one delivery per subscribed webhook' do
    create(:webhook, user:, place_ids: [create(:place, :geofence, user:).id])

    expect { record(:enter) }.to have_enqueued_job(Webhooks::DeliverJob).exactly(:once)
    expect(GeofenceEvent.real.where(user:, event_type: :enter).count).to eq(1)
  end

  it 'stores an event that arrives too late for automations but does not deliver it' do
    expect { record(:enter, occurred_at: 20.minutes.ago) }.not_to have_enqueued_job(Webhooks::DeliverJob)
    expect(GeofenceEvent.sole).to be_skipped_late
  end

  context 'on Dawarich Cloud' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :pro, active_until: 1.year.from_now)
    end

    it 'keeps recording but stops sending once an hour has too many events' do
      create_list(:geofence_event, GeofenceEvent::WEBHOOK_HOURLY_LIMIT, user:, place:, occurred_at: 30.minutes.ago)

      expect { record(:enter) }.not_to have_enqueued_job(Webhooks::DeliverJob)
      expect(GeofenceEvent.order(:id).last).to be_skipped_throttled
    end

    it 'does not count events that were not sent or are older than an hour' do
      create_list(:geofence_event, GeofenceEvent::WEBHOOK_HOURLY_LIMIT, user:, place:, occurred_at: 2.hours.ago)
      create_list(:geofence_event, GeofenceEvent::WEBHOOK_HOURLY_LIMIT, user:, place:, webhook_skip_reason: :late)

      expect { record(:enter) }.to have_enqueued_job(Webhooks::DeliverJob)
    end
  end

  it 'does not cap events on a self-hosted instance' do
    create_list(:geofence_event, GeofenceEvent::WEBHOOK_HOURLY_LIMIT, user:, place:, occurred_at: 30.minutes.ago)

    expect { record(:enter) }.to have_enqueued_job(Webhooks::DeliverJob)
  end

  it 'delivers an event that arrives a few minutes late' do
    expect { record(:enter, occurred_at: 10.minutes.ago) }.to have_enqueued_job(Webhooks::DeliverJob)
  end

  it 'records a repeated enter once, also from concurrent requests' do
    threads = Array.new(2) { Thread.new { ActiveRecord::Base.connection_pool.with_connection { record(:enter) } } }
    threads.each(&:join)
    record(:enter)

    expect(GeofenceEvent.where(user:).count).to eq(1)
    expect(WebhookDelivery.count).to eq(1)
  end

  it 'delivers enter, leave and enter again in quick succession' do
    record(:enter)
    record(:leave)
    record(:enter)

    expect(GeofenceEvent.order(:id).pluck(:event_type)).to eq(%w[enter leave enter])
    expect(WebhookDelivery.count).to eq(3)
  end

  it 'rebuilds lost state from the last real events' do
    record(:enter)
    Sidekiq.redis_pool.with { |redis| redis.call('DEL', "geofence:inside:#{user.id}", "geofence:ready:#{user.id}") }

    expect(record(:enter)).to be_nil
    expect(record(:leave)).to be_present
  end

  it 'stores events but delivers nothing for a Lite user on cloud' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update!(plan: :lite)

    expect { record(:enter) }.not_to have_enqueued_job(Webhooks::DeliverJob)
    expect(GeofenceEvent.count).to eq(1)
  end

  it 'delivers for a Family user on cloud' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update!(plan: :family, active_until: 1.year.from_now)

    expect { record(:enter) }.to have_enqueued_job(Webhooks::DeliverJob)
  end

  it 'treats a busy connection pool like an unavailable Redis' do
    allow(Sidekiq).to receive(:redis_pool).and_raise(ConnectionPool::TimeoutError, 'busy')

    expect { record(:enter, source: :native_app) }.to have_enqueued_job(Webhooks::DeliverJob)
  end

  context 'when Redis is unavailable' do
    before do
      allow(Sidekiq).to receive(:redis_pool).and_raise(RedisClient::CannotConnectError, 'down')
    end

    it 'still records and delivers a transition reported by the phone' do
      expect { record(:enter, source: :native_app) }.to have_enqueued_job(Webhooks::DeliverJob)
    end

    it 'skips server inference without raising' do
      expect(record(:enter)).to be_nil
      expect(GeofenceEvent.count).to eq(0)
    end
  end

  it 'drops a replayed older phone transition that is already recorded' do
    occurred_at = 10.minutes.ago
    first = described_class.call(user:, place:, event_type: :enter, source: :native_app, occurred_at:,
                                 lonlat: 'POINT(13.539 52.437)', apply_state: false)
    replay = described_class.call(user:, place:, event_type: :enter, source: :native_app,
                                  occurred_at: occurred_at + 30.seconds, lonlat: 'POINT(13.539 52.437)',
                                  apply_state: false)

    expect(first).to be_present
    expect(replay).to be_nil
    expect(WebhookDelivery.count).to eq(1)
  end

  it 'stores and delivers an older phone transition without moving state' do
    record(:enter)

    expect(record(:leave, source: :native_app, apply_state: false)).to be_present
    expect(GeofenceEvents::StateStore.new(user).inside_ids).to include(place.id)
  end

  it 'snapshots the place name when recording an event', :place_retention do
    place.update!(name: 'Home')

    expect(record(:enter).reload.place_name).to eq('Home')
  end

  it 'deduplicates a repeated transition after its place is renamed', :place_retention do
    record(:enter, source: :native_app, apply_state: false)
    place.update!(name: 'Renamed home')

    expect { record(:enter, source: :native_app, apply_state: false) }.not_to change(GeofenceEvent, :count)
  end
end
