# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Immich enrichment confirmation' do
  let(:user) { create(:user, settings: { 'immich_url' => 'http://immich.test', 'immich_api_key' => 'test-key' }) }
  let(:assets) { [{ 'immich_asset_id' => 'asset-1', 'latitude' => 52.52, 'longitude' => 13.405 }] }

  it 'does not claim that an accepted asynchronous update has been saved' do
    stub_request(:put, 'http://immich.test/api/assets/asset-1')
      .to_return(status: 200, body: '{}', headers: { 'content-type' => 'application/json' })

    result = Immich::EnrichPhotos.new(user, assets).call

    expect(result).to include(enriched: 0, pending: 1, failed: 0)
  end
end
