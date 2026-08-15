# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Photos API caching of empty results', type: :request do
  let(:user) { create(:user, :with_photoprism_integration) }
  let(:start_date) { '2026-01-13T00:00:00.000+00:00' }
  let(:end_date)   { '2026-01-20T23:59:59.999+00:00' }

  let(:photo_data) do
    [
      {
        'id' => 1,
        'latitude' => 35.6762,
        'longitude' => 139.6503,
        'localDateTime' => '2024-01-01T00:00:00.000Z',
        'originalFileName' => 'photo1.jpg',
        'city' => 'Tokyo',
        'state' => 'Tokyo',
        'country' => 'Japan',
        'type' => 'photo',
        'source' => 'photoprism'
      }
    ]
  end

  before { Rails.cache.clear }

  it 'returns fresh upstream photos after a prior empty result for the same range' do
    allow_any_instance_of(Photos::Search).to receive(:errors).and_return([])

    allow_any_instance_of(Photos::Search).to receive(:call).and_return([])
    get '/api/v1/photos', params: { api_key: user.api_key, start_date: start_date, end_date: end_date }
    expect(JSON.parse(response.body)).to eq([])

    allow_any_instance_of(Photos::Search).to receive(:call).and_return(photo_data)
    get '/api/v1/photos', params: { api_key: user.api_key, start_date: start_date, end_date: end_date }

    expect(JSON.parse(response.body)).to eq(photo_data)
  end

  it 'still caches non-empty results for the configured TTL' do
    allow_any_instance_of(Photos::Search).to receive(:errors).and_return([])
    allow_any_instance_of(Photos::Search).to receive(:call).and_return(photo_data)

    get '/api/v1/photos', params: { api_key: user.api_key, start_date: start_date, end_date: end_date }
    expect(JSON.parse(response.body)).to eq(photo_data)

    allow_any_instance_of(Photos::Search).to receive(:call).and_raise('upstream called despite warm cache')
    get '/api/v1/photos', params: { api_key: user.api_key, start_date: start_date, end_date: end_date }

    expect(JSON.parse(response.body)).to eq(photo_data)
  end
end
