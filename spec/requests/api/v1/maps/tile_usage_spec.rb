# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Maps::TileUsage', type: :request do
  describe 'POST /api/v1/maps/tile_usage' do
    let(:tile_count) { 5 }
    let(:track_service) { instance_double(Metrics::Maps::TileUsage::Track) }
    let(:user) { create(:user) }

    before do
      allow(Metrics::Maps::TileUsage::Track).to receive(:new).with(user.id, tile_count).and_return(track_service)
      allow(track_service).to receive(:call)
    end

    context 'when user is authenticated' do
      it 'tracks tile usage' do
        post '/api/v1/maps/tile_usage',
             params: { tile_usage: { count: tile_count } },
             headers: { 'Authorization' => "Bearer #{user.api_key}" }

        expect(Metrics::Maps::TileUsage::Track).to have_received(:new).with(user.id, tile_count)
        expect(track_service).to have_received(:call)
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when user is not authenticated' do
      it 'returns unauthorized' do
        post '/api/v1/maps/tile_usage', params: { tile_usage: { count: tile_count } }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
