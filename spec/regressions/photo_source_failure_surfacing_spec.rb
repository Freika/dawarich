# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Photo source failures are surfaced to the caller', type: :request do
  let(:user) do
    create(
      :user,
      settings: {
        'immich_url' => 'http://immich.local',
        'immich_api_key' => 'test_api_key'
      }
    )
  end

  before { allow(Rails.cache).to receive(:read).and_return(nil) }

  def get_photos
    get '/api/v1/photos',
        params: { api_key: user.api_key, start_date: '2026-06-20T00:00:00Z', end_date: '2026-06-26T00:00:00Z' }
  end

  context 'when the Immich instance is unreachable' do
    before { stub_request(:post, /immich\.local/).to_timeout }

    it 'reports the failure to the caller' do
      get_photos

      expect(response).not_to have_http_status(:ok)
    end
  end

  context 'when the Immich instance rejects the request' do
    before do
      stub_request(:post, /immich\.local/)
        .to_return(status: 500, body: { error: 'boom' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'reports the failure to the caller' do
      get_photos

      expect(response).not_to have_http_status(:ok)
    end

    it 'does not present the failure as an empty photo list' do
      get_photos

      expect(JSON.parse(response.body)).not_to eq([])
    end
  end

  context 'when one source fails and another still returns photos' do
    let(:user) do
      create(
        :user,
        settings: {
          'immich_url' => 'http://immich.local',
          'immich_api_key' => 'test_api_key',
          'photoprism_url' => 'http://photoprism.local',
          'photoprism_api_key' => 'test_api_key'
        }
      )
    end

    before do
      stub_request(:post, /immich\.local/).to_return(status: 500, body: '{}',
                                                     headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, /photoprism\.local/).to_return(
        { status: 200,
          body: [{ 'Hash' => 'abc', 'Type' => 'image', 'TakenAt' => '2026-06-22T10:00:00Z',
                   'Lat' => 52.5, 'Lng' => 13.4 }].to_json,
          headers: { 'Content-Type' => 'application/json' } },
        { status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' } }
      )
    end

    it 'still returns the photos that were retrieved' do
      get_photos

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(1)
    end

    it 'names the failed source in a response header' do
      get_photos

      expect(response.headers['X-Photo-Source-Errors']).to eq('immich')
    end
  end
end
