# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe Trips::CalculationEventsBroadcaster do
  let(:trip) { create(:trip) }

  before do
    %i[broadcast_refresh_to broadcast_update_to broadcast_replace_to].each do |method|
      allow(Turbo::StreamsChannel).to receive(method)
    end
  end

  after do
    described_class.stop
    broadcaster_threads.each do |thread|
      thread.kill
      thread.join
    end
    expect(broadcaster_threads).to be_empty
  end

  def event!(trip_id, kind, failed: false)
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, trip_id, kind, failed]))
      INSERT INTO phoenix.trip_events (trip_id, kind, distance_unit, failed, created_at) VALUES (?, ?, 'mi', ?, now())
    SQL
  end

  def broadcaster_threads
    Thread.list.select { _1.name == described_class::THREAD_NAME }
  end

  it 'does nothing before Phoenix ever migrated' do
    expect(described_class.drain_once).to eq(0)
  end

  it 'turns each event into the broadcast the Sidekiq job used to send, and consumes it' do
    phoenix_tables!
    %w[path distance countries].each { event!(trip.id, _1) }
    event!(trip.id, 'finished', failed: true)

    expect(described_class.drain_once).to eq(4)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_to).with(trip)
    expect(Turbo::StreamsChannel).to have_received(:broadcast_update_to)
      .with(trip, target: 'trip_distance', partial: 'trips/distance', locals: { trip:, distance_unit: 'mi' })
    expect(Turbo::StreamsChannel).to have_received(:broadcast_update_to)
      .with(trip, target: 'trip_countries', partial: 'trips/countries', locals: { trip:, distance_unit: 'mi' })
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      .with(trip, target: 'trip_recalculate_frame', partial: 'trips/recalculate_button', locals: { trip:, error: true })
    expect(described_class.drain_once).to eq(0)
  end

  it 'drops events of a deleted trip without broadcasting' do
    phoenix_tables!
    event!(987_654, 'finished')

    expect(described_class.drain_once).to eq(1)
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
  end

  it 'starts one named broadcaster thread even when started twice' do
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

    expect(broadcaster_threads).to contain_exactly(thread)
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
    expect(broadcaster_threads).to be_empty

    described_class.start
    second_thread = entered.pop

    expect(second_thread).not_to equal(first_thread)
    expect(broadcaster_threads).to contain_exactly(second_thread)
  end

  it 'logs a database error, backs off, and keeps draining' do
    backoff = Queue.new
    drained = Queue.new
    release = Queue.new
    calls = 0
    allow(Rails).to receive(:env).and_return('production'.inquiry)
    allow(Rails.logger).to receive(:warn)
    allow(described_class).to receive(:sleep) { |seconds| backoff << seconds }
    allow(described_class).to receive(:drain_once) do
      calls += 1
      raise ActiveRecord::StatementInvalid, 'transient database failure' if calls == 1

      drained << true
      release.pop
      1
    end

    described_class.start

    expect(Timeout.timeout(1) { backoff.pop }).to eq(5)
    expect(Timeout.timeout(1) { drained.pop }).to be(true)
    expect(Rails.logger).to have_received(:warn).with('[Trips] calculation events: ActiveRecord::StatementInvalid')
  end
end
