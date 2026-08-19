# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::SharedLinks do
  subject(:service) { described_class.new(user) }

  let(:user) { create(:user, :with_immich_integration) }
  let(:response) do
    instance_double(
      HTTParty::Response,
      success?: true,
      code: 200,
      headers: { 'content-type' => 'application/json' },
      body: payload.to_json
    )
  end
  let(:payload) do
    [
      {
        'id' => 'shared-1',
        'slug' => 'summer-public',
        'description' => 'Summer public share',
        'album' => { 'id' => 'album-1', 'albumName' => 'Summer', 'assetCount' => 12 }
      },
      {
        'id' => 'asset-only',
        'slug' => 'asset-public',
        'album' => nil
      },
      {
        'id' => 'legacy-without-slug',
        'slug' => nil,
        'album' => { 'id' => 'album-2', 'albumName' => 'Private' }
      }
    ]
  end

  before do
    Rails.cache.clear
    allow(HTTParty).to receive(:get).and_return(response)
  end

  it 'loads shared links from Immich with the configured API key' do
    expect(HTTParty).to receive(:get).with(
      'https://immich.example.com/api/shared-links',
      hash_including(
        headers: {
          'x-api-key' => '1234567890',
          'accept' => 'application/json'
        },
        timeout: 10
      )
    ).and_return(response)

    service.call
  end

  it 'returns only album-based links with a public slug' do
    expect(service.call).to contain_exactly(payload.first)
  end

  it 'returns cached links without making another request' do
    expect(HTTParty).to receive(:get).once.and_return(response)

    first_result = service.call
    second_result = service.call

    expect(second_result).to eq(first_result)
  end

  it 'returns a cached empty array without making another request' do
    Rails.cache.write("immich-shared-links:user:#{user.id}", [])

    expect(HTTParty).not_to receive(:get)

    expect(service.call).to eq([])
  end
end
