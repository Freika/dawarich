# frozen_string_literal: true

require 'rails_helper'

# Temporary: pins what the HTTParty-based clients do today in the cases where
# Net::HTTP behaves differently, so the move to Integrations::Transport cannot
# change them unnoticed. Deleted once every integration is on the transport.
RSpec.describe 'Integration HTTP behaviour before the transport' do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

  describe 'credentials embedded in the URL' do
    it 'sends them as basic auth next to an x-api-key header (Immich)' do
      request = stub_request(:post, 'http://immich.lan/api/search/metadata')
                .with(basic_auth: %w[proxyuser proxypass], headers: { 'x-api-key' => 'key' })
                .to_return(status: 200, body: { assets: { items: [] } }.to_json,
                           headers: { 'Content-Type' => 'application/json' })

      result = Immich::ConnectionTester.new('http://proxyuser:proxypass@immich.lan', 'key').call

      expect(request).to have_been_requested
      expect(result[:success]).to be true
    end

    it 'replaces a Bearer Authorization header with basic auth (Photoprism)' do
      sent = nil
      stub_request(:get, %r{\Ahttp://photoprism\.lan/api/v1/photos})
        .to_return do |req|
          sent = req.headers['Authorization']
          { status: 200, body: '[]', headers: { 'Content-Type' => 'application/json' } }
        end

      Photoprism::ConnectionTester.new('http://proxyuser:proxypass@photoprism.lan', 'key').call

      expect(sent).to eq("Basic #{Base64.strict_encode64('proxyuser:proxypass')}")
    end
  end

  describe 'a redirect answer' do
    it 'is followed by a GET client (AirTrail)' do
      stub_request(:get, 'http://airtrail.lan/api/flight/list?scope=mine')
        .to_return(status: 302, headers: { 'Location' => 'http://airtrail.lan/final' })
      final = stub_request(:get, 'http://airtrail.lan/final')
              .to_return(status: 200, body: { success: true, flights: [] }.to_json)

      AirTrail::Client.new('http://airtrail.lan', 'key').flights

      expect(final).to have_been_requested
    end
  end

  describe 'the response object' do
    it 'has an Integer code and case-insensitive headers' do
      stub_request(:get, 'http://airtrail.lan/probe')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      response = HTTParty.get('http://airtrail.lan/probe')

      expect(response.code).to eq(200)
      expect(response.headers['content-type']).to eq('application/json')
      expect(response.headers['Content-Type']).to eq('application/json')
    end
  end
end
