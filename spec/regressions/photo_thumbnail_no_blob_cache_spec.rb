# frozen_string_literal: true

require 'rails_helper'

class ThumbnailFakeResponse
  attr_reader :body, :code

  def initialize(body)
    @body = body
    @code = 200
  end

  def success?
    true
  end
end

RSpec.describe 'Photo thumbnail does not cache binary blobs in Rails.cache', type: :request do
  let(:user) { create(:user, :with_immich_integration) }
  let(:photo_id) { 'asset-abc-123' }
  let(:body) { 'X' * 100_000 }

  before do
    allow(HTTParty).to receive(:get).and_return(ThumbnailFakeResponse.new(body))
    Rails.cache.clear
  end

  it 'never writes a photo_thumbnail_* entry into Rails.cache' do
    expect(Rails.cache).not_to receive(:write)
      .with(a_string_matching(/\Aphoto_thumbnail_/), anything, anything)

    get "/api/v1/photos/#{photo_id}/thumbnail",
        params: { api_key: user.api_key, source: 'immich' }

    expect(response).to have_http_status(:ok)
    expect(response.body.bytesize).to eq(body.bytesize)
  end

  it 'sets a private Cache-Control header so browsers cache instead of Redis' do
    get "/api/v1/photos/#{photo_id}/thumbnail",
        params: { api_key: user.api_key, source: 'immich' }

    cache_control = response.headers['Cache-Control']
    expect(cache_control).to include('private')
    expect(cache_control).to match(/max-age=\d+/)
  end

  it 'fetches upstream every request (no server-side memoization between calls)' do
    expect(HTTParty).to receive(:get).twice.and_return(ThumbnailFakeResponse.new(body))

    2.times do
      get "/api/v1/photos/#{photo_id}/thumbnail",
          params: { api_key: user.api_key, source: 'immich' }
    end
  end
end
