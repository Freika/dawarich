# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::ConnectionTester do
  subject(:result) { described_class.new(url, api_key).call }

  let(:url) { 'https://immich.example.com' }
  let(:api_key) { 'test_api_key_123' }
  let(:metadata_url) { "#{url}/api/search/metadata" }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def stub_metadata(status: 200, body: { assets: { items: [{ id: 'asset-123' }] } }.to_json)
    stub_request(:post, metadata_url).to_return(status:, body:, headers: json)
  end

  def stub_thumbnail(asset_id = 'asset-123', status: 200, body: 'image-bytes')
    stub_request(:get, "#{url}/api/assets/#{asset_id}/thumbnail?size=preview").to_return(status:, body:)
  end

  describe 'missing fields' do
    [nil, ''].each do |blank|
      it "reports a missing URL for #{blank.inspect}" do
        expect(described_class.new(blank, api_key).call)
          .to include(success: false, reason: 'missing_fields', error: 'Immich URL is missing')
      end

      it "reports a missing API key for #{blank.inspect}" do
        expect(described_class.new(url, blank).call)
          .to include(success: false, reason: 'missing_fields', error: 'Immich API key is missing')
      end
    end
  end

  it 'verifies the connection when the search and the thumbnail both answer' do
    metadata = stub_metadata.with(headers: { 'x-api-key' => api_key, 'Accept' => 'application/json' })
    thumbnail = stub_thumbnail.with(headers: { 'x-api-key' => api_key })

    expect(result).to eq(success: true, message: 'Immich connection verified')
    expect(metadata).to have_been_requested
    expect(thumbnail).to have_been_requested
  end

  it 'asks for one asset from today' do
    stub_thumbnail
    expected = { 'size' => 1, 'page' => 1, 'order' => 'asc', 'withExif' => true }
    metadata = stub_metadata.with do |request|
      body = JSON.parse(request.body)
      body.slice(*expected.keys) == expected && body['takenAfter'].present?
    end

    result

    expect(metadata).to have_been_requested
  end

  it 'verifies the connection without a thumbnail check when the library is empty' do
    stub_metadata(body: { assets: { items: [] } }.to_json)

    expect(result).to eq(success: true, message: 'Immich connection verified')
    expect(a_request(:get, /thumbnail/)).not_to have_been_made
  end

  it 'treats an unparsable search body as an empty library' do
    stub_metadata(body: 'not json')

    expect(result).to eq(success: true, message: 'Immich connection verified')
  end

  it 'treats a search body without assets as an empty library' do
    stub_metadata(body: { other: 'shape' }.to_json)

    expect(result).to eq(success: true, message: 'Immich connection verified')
  end

  it 'escapes the asset id in the thumbnail path' do
    stub_metadata(body: { assets: { items: [{ id: '../admin' }] } }.to_json)
    thumbnail = stub_request(:get, "#{url}/api/assets/..%2Fadmin/thumbnail?size=preview").to_return(status: 200)

    result

    expect(thumbnail).to have_been_requested
  end

  it 'reports rejected credentials' do
    stub_metadata(status: 401, body: '{}')

    expect(result).to include(success: false, reason: 'credentials', error: 'Immich connection failed: 401')
  end

  it 'reports another failing status as a settings problem' do
    stub_metadata(status: 500, body: '{}')

    expect(result).to include(success: false, reason: 'check_settings', error: 'Immich connection failed: 500')
  end

  it 'names the missing asset.view permission' do
    stub_metadata
    stub_thumbnail(status: 403, body: { message: 'Missing required permission: asset.view' }.to_json)

    expect(result).to include(success: false, reason: 'credentials',
                              error: 'Immich API key missing permission: asset.view')
  end

  it 'reports a failing thumbnail check with its status' do
    stub_metadata
    stub_thumbnail(status: 500, body: 'boom')

    expect(result).to include(success: false, reason: 'check_settings', error: 'Immich thumbnail check failed: 500')
  end

  it 'reports a timeout as unreachable' do
    stub_request(:post, metadata_url).to_timeout

    expect(result).to include(success: false, reason: 'unreachable')
    expect(result[:error]).to start_with('Immich connection failed: ')
  end

  it 'reports a certificate failure as such' do
    stub_request(:post, metadata_url).to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed'))

    expect(result).to include(success: false, reason: 'certificate')
    expect(result[:error]).to include('certificate verify failed')
  end

  it 'does not follow a redirect' do
    stub_request(:post, metadata_url).to_return(status: 301, headers: { 'Location' => 'https://other.example.com/' })
    followed = stub_request(:any, 'https://other.example.com/')

    expect(result).to include(success: false, reason: 'unreachable')
    expect(result[:error]).to include('redirect')
    expect(followed).not_to have_been_requested
  end

  it 'refuses a URL that resolves to a blocked address without sending a request' do
    stub_host_addresses('immich.example.com', '169.254.169.254')
    metadata = stub_metadata

    expect(result).to include(success: false, reason: 'unreachable')
    expect(metadata).not_to have_been_requested
  end
end
