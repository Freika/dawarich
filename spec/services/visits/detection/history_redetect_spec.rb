# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::HistoryRedetect do
  let(:user) { create(:user) }
  let(:base_ts) { Time.zone.parse('2026-01-05 09:00:00 UTC').to_i }

  before do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: false, store_geodata?: false)
  end

  def seed_cluster(at: base_ts)
    6.times do |i|
      create(:point, user: user, latitude: 51.3402, longitude: 12.3712,
                     lonlat: 'POINT(12.3712 51.3402)', timestamp: at + (i * 60), accuracy: 10)
    end
  end

  it 'redetects the full point history and reports counts' do
    seed_cluster
    seed_cluster(at: base_ts + 45.days.to_i)

    result = described_class.new(user).call

    expect(result.visits_created).to eq(2)
    expect(result.months_total).to be >= 2
    expect(result.months_failed).to be_empty
    expect(user.visits.count).to eq(2)
  end

  it 'returns an empty result for a user without points' do
    result = described_class.new(user).call

    expect(result.visits_created).to eq(0)
    expect(result.months_total).to eq(0)
  end

  it 'backfills confidence on legacy scoreless visits without touching their status' do
    seed_cluster
    legacy = create(:visit, user: user, status: :confirmed, confidence: nil,
                    started_at: Time.zone.at(base_ts + 10.days.to_i),
                    ended_at: Time.zone.at(base_ts + 10.days.to_i + 3600), duration: 60)

    described_class.new(user).call

    legacy.reload
    expect(legacy.confidence).to be_present
    expect(legacy.status).to eq('confirmed')
    expect(legacy.detection_version).to be_nil
  end

  it 'records failed months and keeps going' do
    seed_cluster
    seed_cluster(at: base_ts + 45.days.to_i)

    call_count = 0
    allow(Visits::SmartDetect).to receive(:new).and_wrap_original do |original, *args, **kwargs|
      call_count += 1
      raise ActiveRecord::StatementInvalid, 'boom' if call_count == 1

      original.call(*args, **kwargs)
    end
    allow(ExceptionReporter).to receive(:call)

    result = described_class.new(user).call

    expect(result.months_failed.size).to eq(1)
    expect(result.visits_created).to be >= 1
  end
end
