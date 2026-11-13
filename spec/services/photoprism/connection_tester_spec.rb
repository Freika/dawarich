# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photoprism::ConnectionTester do
  subject(:result) { described_class.new(url, api_key).call }

  let(:url) { 'https://photoprism.example.com' }
  let(:api_key) { 'test_api_key_123' }
  let(:photos_url) { "#{url}/api/v1/photos" }

  def stub_photos(status: 200, body: '[]')
    stub_request(:get, photos_url).with(query: { count: '1', public: 'true' })
                                  .to_return(status:, body:, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'missing fields' do
    [nil, ''].each do |blank|
      it "reports a missing URL for #{blank.inspect}" do
        expect(described_class.new(blank, api_key).call)
          .to include(success: false, reason: 'missing_fields', error: 'Photoprism URL is missing')
      end

      it "reports a missing API key for #{blank.inspect}" do
        expect(described_class.new(url, blank).call)
          .to include(success: false, reason: 'missing_fields', error: 'Photoprism API key is missing')
      end
    end
  end

  it 'verifies the connection with a one-photo request carrying the bearer token' do
    request = stub_photos.with(headers: { 'Authorization' => "Bearer #{api_key}", 'Accept' => 'application/json' })

    expect(result).to eq(success: true, message: 'Photoprism connection verified')
    expect(request).to have_been_requested
  end

  it 'reports rejected credentials' do
    stub_photos(status: 401)

    expect(result).to include(success: false, reason: 'credentials', error: 'Photoprism connection failed: 401')
  end

  it 'reports another failing status as a settings problem' do
    stub_photos(status: 500)

    expect(result).to include(success: false, reason: 'check_settings', error: 'Photoprism connection failed: 500')
  end

  it 'reports a timeout as unreachable' do
    stub_request(:get, photos_url).with(query: hash_including({})).to_timeout

    expect(result).to include(success: false, reason: 'unreachable')
    expect(result[:error]).to start_with('Photoprism connection failed: ')
  end

  it 'reports a certificate failure as such' do
    stub_request(:get, photos_url).with(query: hash_including({}))
                                  .to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed'))

    expect(result).to include(success: false, reason: 'certificate')
  end

  it 'does not follow a redirect' do
    stub_request(:get, photos_url).with(query: hash_including({}))
                                  .to_return(status: 302, headers: { 'Location' => 'https://other.example.com/' })
    followed = stub_request(:any, 'https://other.example.com/')

    expect(result).to include(success: false, reason: 'unreachable')
    expect(followed).not_to have_been_requested
  end

  it 'refuses a URL that resolves to a blocked address without sending a request' do
    stub_host_addresses('photoprism.example.com', '169.254.169.254')
    request = stub_photos

    expect(result).to include(success: false, reason: 'unreachable')
    expect(request).not_to have_been_requested
  end

  it 'keeps verification on for a legacy "0" skip flag' do
    stub_photos
    captured = nil
    allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |http| captured = http }
    end

    described_class.new(url, api_key, skip_ssl_verification: '0').call

    expect(captured.verify_mode).not_to eq(OpenSSL::SSL::VERIFY_NONE)
  end
end
