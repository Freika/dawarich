# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::PostIngestActions do
  subject(:call_service) do
    described_class.new(
      user_id: user.id,
      timestamps: [1_700_000_000],
      points: [],
      payload: []
    ).call
  end

  let(:user) { create(:user) }

  before do
    allow(Points::AnomalyFilterJob).to receive(:perform_later)
    allow_any_instance_of(Tracks::RealtimeDebouncer).to receive(:trigger)
    allow_any_instance_of(Tracks::BackfillScheduler).to receive(:call)
    allow_any_instance_of(Visits::RealtimeDebouncer).to receive(:trigger)
    allow_any_instance_of(Points::LiveBroadcaster).to receive(:call)
  end

  [
    RedisClient::CannotConnectError,
    RedisClient::ReadTimeoutError,
    RedisClient::WriteTimeoutError,
    RedisClient::CheckoutTimeoutError,
    ConnectionPool::TimeoutError
  ].each do |error_class|
    it "retains pending work when #{error_class} is raised" do
      allow(Points::AnomalyFilterJob).to receive(:perform_later).and_raise(error_class, 'down')
      allow(Rails.logger).to receive(:warn)

      expect { call_service }.to change(Points::PostIngestBatch, :count).by(1)
      expect(Rails.logger).to have_received(:warn)
        .with(/event=points.post_ingest_unavailable.*error=#{error_class}/)
    end
  end

  it 'clears pending work after all durable actions are scheduled' do
    expect { call_service }.not_to change(Points::PostIngestBatch, :count)
  end

  it 'does not fail ingestion when live broadcasting loses its Redis connection' do
    allow_any_instance_of(Points::LiveBroadcaster).to receive(:call)
      .and_raise(Redis::BaseConnectionError, 'down')
    allow(Rails.logger).to receive(:warn)

    expect { call_service }.not_to raise_error
    expect(Points::PostIngestBatch.count).to eq(0)
  end

  it 'does not hide unexpected application errors' do
    allow(Points::AnomalyFilterJob).to receive(:perform_later).and_raise(StandardError, 'bug')

    expect { call_service }.to raise_error(StandardError, 'bug')
    expect(Points::PostIngestBatch.count).to eq(1)
  end
end
