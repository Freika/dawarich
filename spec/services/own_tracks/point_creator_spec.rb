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

  context 'when params are invalid' do
    let(:point_params) { { lat: nil } }

    it 'returns an empty array' do
      expect(call_service).to eq([])
    end
  end
end
