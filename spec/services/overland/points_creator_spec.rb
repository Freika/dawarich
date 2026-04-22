# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Overland::PointsCreator do
  subject(:call_service) { described_class.new(payload, user.id).call }

  let(:user) { create(:user) }
  let(:file_path) { 'spec/fixtures/files/overland/geodata.json' }
  let(:payload_hash) { JSON.parse(File.read(file_path)) }

  context 'with a hash payload' do
    let(:payload) { payload_hash }

    it 'creates points synchronously' do
      expect { call_service }.to change { Point.where(user:).count }.by(1)
    end

    it 'returns the created points with coordinates' do
      result = call_service

      expect(result.first).to include('id', 'timestamp', 'longitude', 'latitude')
    end

    it 'does not duplicate existing points' do
      call_service

      expect { call_service }.not_to(change { Point.where(user:).count })
    end

    it 'increments points_count only for newly inserted points' do
      call_service
      user.reload
      count_after_first = user.points_count

      # Second call with same data should not change the counter
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
  end

  context 'with a locations array payload' do
    let(:payload) { payload_hash['locations'] }

    it 'processes the array successfully' do
      expect { call_service }.to change { Point.where(user:).count }.by(1)
    end
  end

  context 'with geofence evaluation' do
    let(:area) { create(:area, user: user, latitude: 37.3318, longitude: -122.030581, radius: 500) }

    before do
      area
      GeofenceEvents::Evaluator::StateStore.reset!(user)
    end

    it 'records a geofence enter event for a point inside an area' do
      expect do
        described_class.new(payload_hash, user.id).call
      end.to change(GeofenceEvent, :count).by(1)

      expect(GeofenceEvent.last.event_type).to eq('enter')
      expect(GeofenceEvent.last.source).to eq('server_inferred')
    end
  end

  context 'with invalid data' do
    let(:payload) { { 'locations' => [{ 'properties' => { 'timestamp' => nil } }] } }

    it 'returns an empty array' do
      expect(call_service).to eq([])
    end
  end
end
