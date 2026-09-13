# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Traccar::PointCreator do
  subject(:call_service) { described_class.new(point_params, user.id).call }

  let(:user) { create(:user) }
  let(:point_params) do
    {
      device_id: 'iphone-frey',
      location: {
        timestamp: '2026-04-23T12:34:56Z',
        latitude: 52.52,
        longitude: 13.405,
        accuracy: 5,
        speed: 1.4,
        altitude: 42
      },
      battery: { level: 0.85, is_charging: true },
      activity: { type: 'walking' }
    }
  end

  context 'when the payload is at Null Island (0,0)' do
    let(:point_params) do
      super().tap { |params| params[:location] = params[:location].merge(latitude: 0.0, longitude: 0.0) }
    end

    it 'drops the point and returns an empty array' do
      expect { expect(call_service).to eq([]) }.not_to(change { Point.where(user:).count })
    end
  end

  it 'creates a point' do
    expect { call_service }.to change { Point.where(user:).count }.by(1)
  end

  it 'returns created point coordinates' do
    result = call_service

    expect(result.first).to include('id', 'timestamp', 'longitude', 'latitude')
  end

  it 'avoids duplicate points' do
    call_service

    expect { call_service }.not_to(change { Point.where(user:).count })
  end

  it 'detaches an archived point from its stale archive when a duplicate arrives with different raw_data' do
    call_service
    point = Point.where(user:).last
    archive = create(:points_raw_data_archive, user: user)
    point.update_columns(raw_data_archived: true, raw_data_archive_id: archive.id)

    described_class.new(point_params.merge(battery: { level: 0.5, is_charging: false }), user.id).call

    point.reload
    expect(point.raw_data_archived).to be false
    expect(point.raw_data_archive_id).to be_nil
  end

  it 'updates points_count to match actual point count' do
    call_service
    user.reload

    expect(user.points_count).to eq(Point.where(user_id: user.id).count)
  end

  it 'does not inflate points_count on duplicate submissions' do
    call_service
    user.reload
    count_after_first = user.points_count

    expect do
      call_service
      user.reload
    end.not_to(change { user.points_count })
    expect(user.points_count).to eq(count_after_first)
  end

  it 'enqueues an anomaly filter job for inserted points' do
    expect { call_service }.to have_enqueued_job(Points::AnomalyFilterJob).with(user.id, anything, anything)
  end

  it 'enqueues VisitSuggestingJob when reverse geocoding is enabled (regression for #1749)' do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)

    expect { call_service }.to have_enqueued_job(VisitSuggestingJob)
      .with(hash_including(user_id: user.id))
  end

  it 'does not enqueue VisitSuggestingJob when reverse geocoding is disabled' do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)

    expect { call_service }.not_to have_enqueued_job(VisitSuggestingJob)
  end

  it 'does not enqueue an anomaly filter job for duplicate submissions' do
    call_service
    expect { call_service }.not_to have_enqueued_job(Points::AnomalyFilterJob)
  end

  context 'when payload is invalid' do
    let(:point_params) { { device_id: 'x' } }

    it 'returns an empty array' do
      expect(call_service).to eq([])
    end

    it 'does not enqueue any jobs' do
      expect { call_service }.not_to have_enqueued_job(Points::AnomalyFilterJob)
    end
  end

  context 'when timestamp is unparseable' do
    before { point_params[:location][:timestamp] = 'not-a-date' }

    it 'does not raise and creates no point' do
      expect { call_service }.not_to(change { Point.where(user:).count })
      expect(call_service).to eq([])
    end
  end
end
