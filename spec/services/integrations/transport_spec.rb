# frozen_string_literal: true

require 'rails_helper'
require 'socket'

RSpec.describe Integrations::Transport do
  let(:self_hosted) { true }

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted) }

  def json_ok(body = '{}')
    { status: 200, body: body, headers: { 'Content-Type' => 'application/json' } }
  end

  # Runs a one-shot HTTP server on 127.0.0.1 and yields its port. Returns the
  # raw request text the server received.
  def with_local_server
    server = TCPServer.new('127.0.0.1', 0)
    received = +''
    thread = Thread.new do
      client = server.accept
      while (line = client.gets) && line != "\r\n"
        received << line
      end
      client.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
      client.close
    end
    yield server.addr[1]
    thread.join(2)
    received
  ensure
    server&.close
  end

  # WebMock replaces Net::HTTP#start, so under it a connection is only opened
  # when the request is sent. These examples need the real connect.
  def allowing_real_connection
    WebMock.disable!
    yield
  ensure
    WebMock.enable!
    WebMock.disable_net_connect!
  end

  describe 'address validation' do
    it 'refuses a URL resolving to the cloud metadata address without sending a request' do
      stub_host_addresses('meta.test', '169.254.169.254')
      request = stub_request(:get, 'http://meta.test/')

      expect { described_class.request(:get, 'http://meta.test/') }
        .to raise_error(described_class::Error) { |error|
          expect(error).to be_blocked
          expect(error).not_to be_retryable
        }
      expect(request).not_to have_been_requested
    end

    context 'on Cloud' do
      let(:self_hosted) { false }

      it 'refuses a private address' do
        stub_host_addresses('immich.lan', '192.168.1.10')

        expect { described_class.request(:get, 'http://immich.lan/') }
          .to raise_error(described_class::Error, &:blocked?)
      end
    end

    it 'requests a private address on self-hosted' do
      stub_host_addresses('immich.lan', '192.168.1.10')
      request = stub_request(:get, 'http://immich.lan/').to_return(json_ok)

      described_class.request(:get, 'http://immich.lan/')

      expect(request).to have_been_requested
    end

    it 'requests a single-label Docker hostname on self-hosted' do
      stub_host_addresses('immich-server', '172.18.0.5')
      request = stub_request(:get, 'http://immich-server:2283/api').to_return(json_ok)

      described_class.request(:get, 'http://immich-server:2283/api')

      expect(request).to have_been_requested
    end

    it 'reports an unresolvable host as retryable, not blocked' do
      stub_unresolvable_host('down.test')

      expect { described_class.request(:get, 'http://down.test/') }
        .to raise_error(described_class::RetryableError) { |error|
          expect(error).not_to be_blocked
          expect(error).to be_unresolvable
        }
    end
  end

  describe '.path_segment' do
    it 'escapes separators and reserved characters' do
      expect(described_class.path_segment('a/b?c#d')).to eq('a%2Fb%3Fc%23d')
    end

    it 'does not let a dot segment climb the path' do
      expect(described_class.path_segment('..')).to eq('%2E%2E')
      expect(described_class.path_segment('.')).to eq('%2E')
    end

    it 'leaves an ordinary id alone' do
      expect(described_class.path_segment('7fe486e3-c3ba.jpg')).to eq('7fe486e3-c3ba.jpg')
    end
  end

  describe 'address pinning' do
    it 'connects to the validated address and keeps the hostname in the Host header' do
      received = with_local_server do |port|
        stub_host_addresses('pinned.test', '127.0.0.1')
        allowing_real_connection do
          response = described_class.request(:get, "http://pinned.test:#{port}/hello")
          expect(response.body).to eq('ok')
        end
      end

      expect(received).to include('GET /hello HTTP/1.1')
      expect(received).to match(/^Host: pinned\.test/i)
    end

    it 'sends the request once when the first address refuses the connection' do
      received = with_local_server do |port|
        stub_host_addresses('dual.test', '::1', '127.0.0.1')
        allowing_real_connection do
          described_class.request(:post, "http://dual.test:#{port}/items", body: '{}')
        end
      end

      expect(received.scan('POST /items').size).to eq(1)
    end

    it 'falls back to the next address when the first refuses the connection' do
      with_local_server do |port|
        stub_host_addresses('dual.test', '::1', '127.0.0.1')
        allowing_real_connection do
          expect(described_class.request(:get, "http://dual.test:#{port}/").body).to eq('ok')
        end
      end
    end
  end

  describe 'proxy environment' do
    around do |example|
      saved = ENV.to_h.slice('http_proxy', 'HTTP_PROXY', 'no_proxy', 'NO_PROXY')
      example.run
    ensure
      %w[http_proxy HTTP_PROXY no_proxy NO_PROXY].each { |key| ENV.delete(key) }
      ENV.update(saved)
    end

    it 'sends the request through the proxy from the environment' do
      stub_host_addresses('behind-proxy.test', '203.0.113.20')
      received = with_local_server do |port|
        ENV['http_proxy'] = "http://127.0.0.1:#{port}"
        allowing_real_connection do
          described_class.request(:get, 'http://behind-proxy.test/data')
        end
      end

      expect(received).to include('GET http://behind-proxy.test/data HTTP/1.1')
    end

    it 'connects directly when no_proxy matches the host' do
      received = with_local_server do |port|
        ENV['http_proxy'] = 'http://127.0.0.1:1'
        ENV['no_proxy'] = 'direct.test'
        stub_host_addresses('direct.test', '127.0.0.1')
        allowing_real_connection do
          described_class.request(:get, "http://direct.test:#{port}/data")
        end
      end

      expect(received).to include('GET /data HTTP/1.1')
    end
  end

  describe 'responses' do
    before { stub_host_addresses('api.test', '203.0.113.5') }

    it 'refuses a redirect and names where it pointed' do
      stub_request(:get, 'http://api.test/old')
        .to_return(status: 302, headers: { 'Location' => 'https://elsewhere.test/new' })
      followed = stub_request(:get, 'https://elsewhere.test/new')

      expect { described_class.request(:get, 'http://api.test/old') }
        .to raise_error(described_class::Error, /elsewhere\.test/) { |error|
          expect(error.status).to eq(302)
          expect(error).not_to be_retryable
        }
      expect(followed).not_to have_been_requested
    end

    it 'returns a non-success answer instead of raising' do
      stub_request(:get, 'http://api.test/secret').to_return(status: 401, body: 'nope')

      response = described_class.request(:get, 'http://api.test/secret')

      expect(response.code).to eq(401)
      expect(response).not_to be_success
      expect(response.body).to eq('nope')
    end

    it 'looks headers up regardless of case' do
      stub_request(:get, 'http://api.test/').to_return(json_ok)

      response = described_class.request(:get, 'http://api.test/')

      expect(response.headers['content-type']).to eq('application/json')
      expect(response.headers['Content-Type']).to eq('application/json')
      expect(response.headers['X-Missing']).to be_nil
    end

    it 'sends a JSON body with POST and PUT' do
      post = stub_request(:post, 'http://api.test/items').with(body: '{"a":1}').to_return(json_ok)
      put = stub_request(:put, 'http://api.test/items/1').with(body: '{"a":2}').to_return(json_ok)

      described_class.request(:post, 'http://api.test/items', body: '{"a":1}')
      described_class.request(:put, 'http://api.test/items/1', body: '{"a":2}')

      expect(post).to have_been_requested
      expect(put).to have_been_requested
    end

    it 'does not treat a 304 without a Location as a redirect' do
      stub_request(:get, 'http://api.test/cached').to_return(status: 304)

      expect(described_class.request(:get, 'http://api.test/cached').code).to eq(304)
    end

    it 'sends non-string header values as text and leaves out nil ones' do
      request = stub_request(:get, 'http://api.test/')
                .with { |req| req.headers['X-Api-Key'] == '12345' && !req.headers.key?('X-Empty') }
                .to_return(json_ok)

      described_class.request(:get, 'http://api.test/', headers: { 'x-api-key' => 12_345, 'x-empty' => nil })

      expect(request).to have_been_requested
    end

    it 'refuses a header value with a line break without echoing it' do
      request = stub_request(:get, 'http://api.test/')

      expect { described_class.request(:get, 'http://api.test/', headers: { 'x-api-key' => "secret\nvalue" }) }
        .to raise_error(described_class::Error) { |error| expect(error.message).not_to include('secret') }
      expect(request).not_to have_been_requested
    end

    it 'rejects an unsupported method' do
      expect { described_class.request(:delete, 'http://api.test/') }.to raise_error(ArgumentError)
    end

    it 'encodes the query like a form' do
      request = stub_request(:get, 'http://api.test/list?a=x%2By+z&page=2').to_return(json_ok)

      described_class.request(:get, 'http://api.test/list', query: { a: 'x+y z', page: 2, skipped: nil })

      expect(request).to have_been_requested
    end
  end

  describe 'credentials embedded in the URL' do
    before { stub_host_addresses('immich.lan', '192.168.1.10') }

    it 'sends them as basic auth' do
      request = stub_request(:get, 'http://immich.lan/').with(basic_auth: %w[proxyuser proxypass]).to_return(json_ok)

      described_class.request(:get, 'http://proxyuser:proxypass@immich.lan/')

      expect(request).to have_been_requested
    end

    it 'replaces a caller Authorization header, as HTTParty did' do
      request = stub_request(:get, 'http://immich.lan/').with(basic_auth: %w[proxyuser proxypass]).to_return(json_ok)

      described_class.request(:get, 'http://proxyuser:proxypass@immich.lan/',
                              headers: { 'Authorization' => 'Bearer token' })

      expect(request).to have_been_requested
    end

    it 'accepts a user name without a password' do
      request = stub_request(:get, 'http://immich.lan/').with(basic_auth: ['tokenonly', '']).to_return(json_ok)

      described_class.request(:get, 'http://tokenonly@immich.lan/')

      expect(request).to have_been_requested
    end

    it 'keeps them out of error messages' do
      stub_request(:get, 'http://immich.lan/').to_raise(Errno::ECONNREFUSED)

      expect { described_class.request(:get, 'http://proxyuser:proxypass@immich.lan/') }
        .to raise_error(described_class::Error) { |error| expect(error.message).not_to include('proxypass') }
    end
  end

  describe 'TLS verification' do
    before { stub_host_addresses('secure.test', '203.0.113.6') }

    def verify_mode_for(skip, url: 'https://secure.test/')
      stub_request(:get, url).to_return(json_ok)
      captured = nil
      allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |http| captured = http }
      end

      described_class.request(:get, url, skip_ssl_verification: skip)
      captured.verify_mode
    end

    ['0', 'false', false, nil].each do |value|
      it "keeps verification on for #{value.inspect}" do
        expect(verify_mode_for(value)).not_to eq(OpenSSL::SSL::VERIFY_NONE)
      end
    end

    [true, '1', 'true'].each do |value|
      it "turns verification off for #{value.inspect}" do
        expect(verify_mode_for(value)).to eq(OpenSSL::SSL::VERIFY_NONE)
      end
    end

    it 'never touches verification for plain http' do
      expect(verify_mode_for(true, url: 'http://secure.test/')).not_to eq(OpenSSL::SSL::VERIFY_NONE)
    end
  end

  describe 'network failures' do
    before { stub_host_addresses('flaky.test', '203.0.113.7') }

    it 'wraps a read timeout as retryable' do
      stub_request(:get, 'http://flaky.test/').to_raise(Net::ReadTimeout)

      expect { described_class.request(:get, 'http://flaky.test/') }
        .to raise_error(described_class::RetryableError) { |error|
          expect(error.cause).to be_a(Net::ReadTimeout)
          expect(error).not_to be_certificate
        }
    end

    it 'marks a certificate failure' do
      stub_request(:get, 'https://flaky.test/').to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed'))

      expect { described_class.request(:get, 'https://flaky.test/') }
        .to raise_error(described_class::RetryableError, /certificate verify failed/, &:certificate?)
    end

    it 'wraps system call errors outside the usual list' do
      stub_request(:get, 'http://flaky.test/').to_raise(Errno::EADDRNOTAVAIL)

      expect { described_class.request(:get, 'http://flaky.test/') }.to raise_error(described_class::RetryableError)
    end

    it 'wraps a body that cannot be decoded' do
      stub_request(:get, 'http://flaky.test/').to_raise(Zlib::DataError.new('incorrect header check'))

      expect { described_class.request(:get, 'http://flaky.test/') }.to raise_error(described_class::RetryableError)
    end

    it 'wraps a malformed response header' do
      stub_request(:get, 'http://flaky.test/').to_raise(Net::HTTPHeaderSyntaxError.new('wrong Content-Length format'))

      expect { described_class.request(:get, 'http://flaky.test/') }.to raise_error(described_class::RetryableError)
    end

    it 'does not send the request again when it fails after the connection was made' do
      stub_host_addresses('flaky.test', '203.0.113.7', '203.0.113.8')
      request = stub_request(:post, 'http://flaky.test/').to_raise(Errno::EHOSTUNREACH)

      expect { described_class.request(:post, 'http://flaky.test/', body: '{}') }
        .to raise_error(described_class::RetryableError)
      expect(request).to have_been_requested.once
    end

    it 'is rescued and classified by the shared connection error lists' do
      stub_request(:get, 'http://flaky.test/').to_raise(Net::ReadTimeout)

      error = begin
        described_class.request(:get, 'http://flaky.test/')
      rescue *Photos::ConnectionErrors::HANDLED => e
        e
      end

      expect(Photos::ConnectionErrors.retryable?(error)).to be true
      expect(Photos::ConnectionErrors::RETRYABLE).to include(described_class::RetryableError)
    end
  end
end
