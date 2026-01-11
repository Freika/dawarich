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

      expect { call_service }.not_to change { Point.where(user:).count }
    end
  end

  context 'with a locations array payload' do
    let(:payload) { payload_hash['locations'] }

    it 'processes the array successfully' do
      expect { call_service }.to change { Point.where(user:).count }.by(1)
    end
  end

  context 'with invalid data' do
    let(:payload) { { 'locations' => [{ 'properties' => { 'timestamp' => nil } }] } }

    it 'returns an empty array' do
      expect(call_service).to eq([])
    end
  end
end
