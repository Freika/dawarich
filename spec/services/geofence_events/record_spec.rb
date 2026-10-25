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
    expect(GeofenceEvent.sole).to be_stale_for_webhooks
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
end
