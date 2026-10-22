# frozen_string_literal: true

require 'rails_helper'
require 'webrick'

RSpec.describe Geocoding::UserLookup do
  def photon_body(city)
    { type: 'FeatureCollection',
      features: [{ type: 'Feature', properties: { city: city, country: 'Germany' },
                   geometry: { type: 'Point', coordinates: [12.3712, 51.3402] } }] }.to_json
  end

  let(:connections) { Queue.new }
  let(:requests) { Queue.new }
  let(:handler_delay) { ->(_latitude) { 0 } }
  let(:server) do
    WEBrick::HTTPServer.new(
      BindAddress: '127.0.0.1', Port: 0, RequestTimeout: 0.5,
      Logger: WEBrick::Log.new(File::NULL), AccessLog: [],
      AcceptCallback: ->(socket) { connections << socket }
    ).tap do |http|
      http.mount_proc('/') do |request, response|
        requests << request.request_line
        sleep(handler_delay.call(request.query['lat']))
        response['Content-Type'] = 'application/json'
        response.body = photon_body(request.query['lat'])
      end
    end
  end
  let(:host) { "127.0.0.1:#{server.config[:Port]}" }
  let(:config) { Geocoding::Config.new(source: :stored, provider: :photon, host: host, use_https: false) }

  around do |example|
    WebMock.disable!
    thread = Thread.new { server.start }
    example.run
  ensure
    server.shutdown
    thread.join
    Geocoding::PersistentHttp.reset!
    WebMock.enable!
  end

  before do
    use_real_geocoding_lookups
    allow_any_instance_of(Geocoder::Lookup::Base).to receive(:cache).and_return(nil)
  end

  def reverse(latitude, longitude, lookup_config = config)
    described_class.build(lookup_config).search(Geocoder::Query.new([latitude, longitude], lookup: :photon))
  end

  it 'sends consecutive lookups over one connection' do
    3.times { |i| expect(reverse(51.34 + i, 12.37)).not_to be_empty }

    expect(requests.size).to eq(3)
    expect(connections.size).to eq(1)
  end

  it 'reconnects after the server drops an idle connection' do
    reverse(51.34, 12.37)
    sleep 1

    expect(reverse(51.35, 12.37).first.city).to eq('51.35')
    expect(connections.size).to eq(2)
  end

  context 'when the server is slow' do
    let(:handler_delay) { ->(_latitude) { 0.6 } }

    it 'raises a lookup timeout and recovers on the next lookup' do
      Geocoder.configure(timeout: 0.2)
      expect { reverse(51.34, 12.37) }.to raise_error(Geocoder::LookupTimeout)

      Geocoder.configure(timeout: 5)
      expect(reverse(51.35, 12.37)).not_to be_empty
    ensure
      Geocoder.configure(timeout: 5)
    end
  end

  context 'when a lookup is interrupted while waiting for its response' do
    let(:handler_delay) { ->(latitude) { latitude == '1.0' ? 0.5 : 0 } }

    it 'does not hand that response to the next lookup' do
      expect { Timeout.timeout(0.1) { reverse(1.0, 12.37) } }.to raise_error(Timeout::Error)
      sleep 0.7

      expect(reverse(2.0, 12.37).first.city).to eq('2.0')
    end
  end

  it 'routes through a configured proxy' do
    Geocoder.configure(http_proxy: host)
    proxied = Geocoding::Config.new(source: :stored, provider: :photon, host: 'photon.invalid', use_https: false)

    expect(reverse(51.34, 12.37, proxied)).not_to be_empty
    expect(requests.pop).to start_with('GET http://photon.invalid/reverse?')
  ensure
    Geocoder.configure(http_proxy: nil)
  end

  it 'does not print provider responses to stdout' do
    expect { reverse(51.34, 12.37) }.not_to output.to_stdout
  end
end
