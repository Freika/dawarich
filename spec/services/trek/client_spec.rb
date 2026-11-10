# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trek::Client do
  let(:source) do
    instance_double(
      TripSource,
      base_url: 'https://trek.example.test',
      api_key: 'trek_test_key',
      skip_ssl_verification: false
    )
  end

  subject(:client) { described_class.new(source) }

  it 'lists trips with a Bearer token' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips')
      .with(headers: { 'Authorization' => 'Bearer trek_test_key', 'Accept' => 'application/json' })
      .to_return(status: 200, body: { trips: [{ id: 12, title: 'Tuscany' }] }.to_json)

    expect(client.trips).to eq([{ 'id' => 12, 'title' => 'Tuscany' }])
  end

  it 'sends credentials embedded in the base URL as basic auth, in place of the Bearer token' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    proxied = instance_double(TripSource, base_url: 'https://gate:secret@trek.example.test', api_key: 'trek_test_key',
                                          skip_ssl_verification: false)
    request = stub_request(:get, 'https://trek.example.test/api/v1/trips')
              .with(basic_auth: %w[gate secret]).to_return(status: 200, body: { trips: [] }.to_json)

    described_class.new(proxied).trips

    expect(request).to have_been_requested
  end

  it 'refuses a base URL that resolves to a blocked address without sending a request' do
    stub_host_addresses('trek.example.test', '169.254.169.254')
    request = stub_request(:get, 'https://trek.example.test/api/v1/trips')

    expect { client.trips }.to raise_error(Trek::Client::Error, /TREK URL was rejected/)
    expect(request).not_to have_been_requested
  end

  it 'reports a host that does not resolve as a rejected URL' do
    stub_unresolvable_host('trek.example.test')

    expect { client.trips }.to raise_error(Trek::Client::Error, /TREK URL was rejected: .*resolve/i)
  end

  it 'reports a redirect as a failed request and keeps its status' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips')
      .to_return(status: 302, headers: { 'Location' => 'https://elsewhere.test/' })

    expect { client.trips }
      .to raise_error(Trek::Client::Error,
                      /\ATREK request failed with HTTP 302\. .*elsewhere\.test.*final URL/) { |error|
        expect(error.status).to eq(302)
      }
  end

  describe 'certificate verification' do
    def capture_connection
      connection = nil
      allow(Net::HTTP).to(receive(:new).and_wrap_original { |original, *args| connection = original.call(*args) })
      stub_request(:get, 'https://trek.example.test/api/v1/trips').to_return(status: 200, body: { trips: [] }.to_json)
      yield
      connection
    end

    it 'verifies the certificate by default' do
      connection = capture_connection { client.trips }

      expect(connection.verify_mode).not_to eq(OpenSSL::SSL::VERIFY_NONE)
    end

    it 'skips certificate verification when the source opts out' do
      allow(source).to receive(:skip_ssl_verification).and_return(true)

      connection = capture_connection { client.trips }

      expect(connection.verify_mode).to eq(OpenSSL::SSL::VERIFY_NONE)
    end

    it 'points to the skip option when the certificate cannot be verified' do
      stub_request(:get, 'https://trek.example.test/api/v1/trips')
        .to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed (unable to get local issuer certificate)'))

      expect { client.trips }.to raise_error(
        Trek::Client::Error, /local issuer certificate.*Skip SSL certificate verification/
      )
    end

    it 'does not suggest skipping verification for an expired certificate' do
      stub_request(:get, 'https://trek.example.test/api/v1/trips')
        .to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed (certificate has expired)'))

      expect { client.trips }.to raise_error(Trek::Client::Error, /certificate has expired/) do |error|
        expect(error.message).not_to include('Skip SSL certificate verification')
      end
    end

    it 'does not suggest skipping verification for a TLS failure unrelated to the certificate' do
      stub_request(:get, 'https://trek.example.test/api/v1/trips')
        .to_raise(OpenSSL::SSL::SSLError.new('wrong version number'))

      expect { client.trips }.to raise_error(Trek::Client::Error, /wrong version number/) do |error|
        expect(error.message).not_to include('Skip SSL certificate verification')
      end
    end

    it 'does not suggest skipping verification when it is already skipped' do
      allow(source).to receive(:skip_ssl_verification).and_return(true)
      stub_request(:get, 'https://trek.example.test/api/v1/trips')
        .to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed'))

      expect { client.trips }.to raise_error(Trek::Client::Error) do |error|
        expect(error.message).not_to include('Skip SSL certificate verification')
      end
    end
  end

  it 'connects to a bracketed IPv6 base URL by its bare address' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    ipv6_source = instance_double(TripSource, base_url: 'http://[fd00::5]:3000', api_key: 'trek_test_key',
                                              skip_ssl_verification: false)
    request = stub_request(:get, 'http://[fd00::5]:3000/api/v1/trips')
              .to_return(status: 200, body: { trips: [] }.to_json)

    expect(described_class.new(ipv6_source).trips).to eq([])
    expect(request).to have_been_requested
  end

  it 'turns a non-success response into an error that retains the status' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips')
      .to_return(status: 401, body: { error: 'unknown key' }.to_json)

    expect { client.trips }.to raise_error(Trek::Client::Error) { |error| expect(error.status).to eq(401) }
  end

  it 'rejects a trip list with an entry that cannot be identified' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips')
      .to_return(status: 200, body: { trips: [{}] }.to_json)

    expect { client.trips }.to raise_error(Trek::Client::Error, /invalid trip/)
  end

  it 'rejects a JSON response whose root is not an object' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips').to_return(status: 200, body: [].to_json)

    expect { client.trips }.to raise_error(Trek::Client::Error, /trip list/)
  end

  it 'rejects a trip list with a non-scalar identifier' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips')
      .to_return(status: 200, body: { trips: [{ id: [] }] }.to_json)

    expect { client.trips }.to raise_error(Trek::Client::Error, /invalid trip/)
  end

  it 'rejects duplicate identifiers after normalization' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips')
      .to_return(status: 200, body: { trips: [{ id: 12 }, { id: '12' }] }.to_json)

    expect { client.trips }.to raise_error(Trek::Client::Error, /invalid trip/)
  end
end
