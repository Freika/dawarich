# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnTracks::PointCreator do
  subject(:call_service) { described_class.new(point_params, user.id).call }

  let(:user) { create(:user) }
  let(:file_path) { 'spec/fixtures/files/owntracks/2024-03.rec' }
  let(:point_params) { OwnTracks::RecParser.new(File.read(file_path)).call.first }

  it 'creates a point immediately' do
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

  it 'updates points_count to match actual point count' do
    call_service
    user.reload

    expect(user.points_count).to eq(Point.where(user_id: user.id).count)
  end

  context 'with geofence evaluation' do
    let(:area) { create(:area, user: user, latitude: 52.225, longitude: 13.332, radius: 100) }

    before do
      area
      GeofenceEvents::Evaluator::StateStore.reset!(user)
    end

    it 'records a geofence enter event for a point inside an area' do
      expect do
        call_service
      end.to change(GeofenceEvent, :count).by(1)

      expect(GeofenceEvent.last.event_type).to eq('enter')
      expect(GeofenceEvent.last.source).to eq('server_inferred')
    end
  end

  context 'when params are invalid' do
    let(:point_params) { { lat: nil } }

    it 'returns an empty array' do
      expect(call_service).to eq([])
    end
  end
end
