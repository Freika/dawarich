# frozen_string_literal: true

require 'rails_helper'
require 'socket'
require 'open3'
require 'timeout'
require 'tmpdir'

RSpec.describe 'S02 mounted Phoenix coexistence privacy', type: :request do
  self.use_transactional_tests = false

  around do |example|
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch('REDIS_URL'))
    @upstream = TCPServer.new('127.0.0.1', 0)
    Dir.mktmpdir('s02-coexistence') do |dir|
      port_file = File.join(dir, 'ports.json')
      child_env = {
        'PHOENIX_TEST_REDIS_URL' => ENV.fetch('REDIS_URL'),
        'S02_UPSTREAM_PORT' => @upstream.addr[1].to_s,
        'S02_PORT_FILE' => port_file,
        'MIX_ENV' => 'test'
      }
      input, output, child = Open3.popen2e(
        child_env, 'mix', 'run', '--no-start', 'scripts/parity/shared_photo_coexistence.exs',
        chdir: Rails.root.join('app-phoenix').to_s
      )
      drain = Thread.new do
        content = output.read
        File.write(ENV.fetch('S02_CHILD_LOG'), content) if ENV['S02_CHILD_LOG']
        content
      end
      begin
        Timeout.timeout(60) { sleep 0.05 until File.exist?(port_file) || !child.alive? }
        raise 'S02 Endpoint exited before readiness; inspect S02_CHILD_LOG' unless File.exist?(port_file)

        @ports = JSON.parse(File.read(port_file))
        example.run
      ensure
        input.puts('stop')
        input.close
        child.join(60)
        raise 'S02 Endpoint did not stop' if child.alive?

        drain.join
      end
    end
  ensure
    @upstream&.close
    SharedLink.where(id: @link&.id).delete_all
    Trip.where(id: @trip&.id).delete_all
    User.where(id: @owner&.id).delete_all
    Rails.cache = previous_cache
  end

  it 'S02C1Rails denies GET and HEAD after Rails warms an excluded trip thumbnail' do
    @owner = create(:user, settings: {
                      'timezone' => 'UTC', 'immich_url' => "http://127.0.0.1:#{@ports.fetch('provider')}",
                      'immich_api_key' => 'synthetic-owner'
                    })
    @trip = create(:trip, user: @owner, started_at: Time.utc(2026, 3, 29),
                         ended_at: Time.utc(2026, 3, 29, 1))
    @link = create(:shared_link, user: @owner, resource_type: :trip, resource_id: @trip.id,
                                settings: { 'show_photos' => true })
    photos = [{ id: 'public-0', source: 'immich', latitude: '52.5', longitude: '13.4',
                capturedAt: '2026-03-29T00:30:00Z' }]
    allow(Photos::Search).to receive(:cached) do |_user, start_date:, end_date:|
      photos.select do |photo|
        Time.iso8601(photo[:capturedAt]).between?(Time.iso8601(start_date), Time.iso8601(end_date))
      end
    end
    image = instance_double(HTTParty::Response, success?: true, body: 'synthetic-jpeg')
    allow(Photos::Thumbnail).to receive(:new).and_return(instance_double(Photos::Thumbnail, call: image))
    path = "/api/v1/shared/#{@link.id}/photos"
    thumb = "#{path}/public-0/thumbnail?source=immich"
    status, body, forwarded = via_endpoint('GET', path)
    expect([status, JSON.parse(body).map { |photo| photo['id'] }, forwarded]).to eq([200, ['public-0'], true])
    expect(via_endpoint('GET', thumb)).to eq([200, 'synthetic-jpeg', true])
    expect(via_endpoint('HEAD', thumb)).to eq([200, '', true])
    @link.update_columns(magic_phrase: 'synthetic-phrase')
    expect(via_endpoint('GET', thumb)).to eq([401, '{"error":"unauthorized"}', true])
    @link.update_columns(magic_phrase: nil)
    @trip.update_columns(started_at: @trip.started_at + 1.day, ended_at: @trip.ended_at + 1.day)
    results = %w[GET HEAD].map { |method| via_endpoint(method, thumb) }
    expect(results).to eq([[404, '', false], [404, '', false]])
    expect(Photos::Thumbnail).to have_received(:new).twice

    get thumb
    expect(response.status).to eq(200)
    head thumb
    expect(response.status).to eq(200)
    puts 'S02C1Rails: Phoenix GET/HEAD 404/404; unchanged Rails GET/HEAD 200/200'
  ensure
    Rails.cache.delete_matched("*shared_link/#{@link.id}/*") if @link
  end

  def via_endpoint(method, path)
    client = TCPSocket.new('127.0.0.1', @ports.fetch('endpoint'))
    client.write("#{method} #{path} HTTP/1.1\r\n" \
                 "Host: localhost\r\nAccept: application/json\r\nConnection: close\r\n\r\n")
    ready = IO.select([client, @upstream], nil, nil, 10)
    raise 'S02 Endpoint did not answer' unless ready

    forwarded = ready.first.include?(@upstream)
    bridge_request(method, path) if forwarded
    wire = Timeout.timeout(10) { client.read }
    header, body = wire.split("\r\n\r\n", 2)
    [header.split[1].to_i, body || '', forwarded]
  ensure
    client&.close
  end

  def bridge_request(method, path)
    socket = @upstream.accept
    raw = +''
    raw << socket.readpartial(4096) until raw.include?("\r\n\r\n")
    expect(raw.lines.first.strip).to eq("#{method} #{path} HTTP/1.1")
    method == 'HEAD' ? head(path) : get(path)
    body = method == 'HEAD' ? '' : response.body
    socket.write("HTTP/1.1 #{response.status} Result\r\n" \
                 "Content-Type: #{response.media_type || 'application/json'}\r\n" \
                 "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  ensure
    socket&.close
  end
end
