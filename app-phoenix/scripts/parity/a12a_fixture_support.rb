# frozen_string_literal: true

require 'socket'
require 'open3'
require 'websocket'
require 'puma'

module A12aFixtureSupport
  PREFIX = 'dawarich_a12a'
  HOST = 'www.example.com'
  ORIGIN = "http://#{HOST}".freeze
  PROTOCOLS = 'actioncable-v1-json, actioncable-unsupported'
  QUIET = 0.5
  NOW = Time.utc(2026, 10, 2, 12, 0, 0)
  PASSWORD = 'phoenix-fixture-password'
  DIR = Rails.root.join('app-phoenix/test/fixtures/a12a')
  COOKIES = JSON.parse(Rails.root.join('app-phoenix/test/fixtures/rails_cookies.json').read)
  UPGRADE = [%w[Upgrade websocket], %w[Connection Upgrade], %w[Sec-WebSocket-Version 13],
             %w[Sec-WebSocket-Key dGhlIHNhbXBsZSBub25jZQ==], ['Origin', ORIGIN],
             ['Sec-WebSocket-Protocol', PROTOCOLS]].freeze
  IDS = {
    'bob' => 971_201, 'carol' => 971_202, 'dave' => 971_203, 'erin' => 971_204, 'frank' => 971_205,
    'family' => 971_211, 'owner_membership' => 971_221, 'member_membership' => 971_222,
    'alice_notification' => 971_301, 'erin_notification' => 971_302, 'bob_notifications' => 971_311,
    'bob_last_notification' => 971_411, 'carol_notifications' => 973_001, 'carol_last_notification' => 973_099,
    'trip_idle' => 971_501, 'trip_cooling' => 971_502,
    'track' => 971_601, 'model_point' => 971_701, 'live_point' => 971_702, 'family_point' => 971_703,
    'import' => 971_801, 'poster' => 971_901
  }.freeze
  SHARES = %w[live_open live_phrase live_expired live_revoked timeline]
           .each_with_index.to_h { |name, i| [name, "a12aface-0000-4000-8000-0000000000a#{i + 1}"] }.freeze
  PHRASE = 'phoenix-a12a-phrase-not-for-production'
  CHANNELS = %w[PointsChannel TracksChannel ImportsChannel MapEditsChannel FamilyLocationsChannel
                SharedLocationChannel Turbo::StreamsChannel ApplicationCable::Channel].freeze
  ROWS = {
    'users' => [%w[id email encrypted_password locked_at deleted_at plan active_until settings status created_at
                   updated_at], 'id'],
    'families' => [%w[id name creator_id created_at updated_at], 'creator_id'],
    'family_memberships' => [%w[id family_id user_id role created_at updated_at], 'user_id'],
    'shared_links' => [%w[id user_id name resource_type resource_id expires_at revoked_at magic_phrase settings
                          created_at updated_at], 'user_id'],
    'notifications' => [%w[id user_id title content kind read_at created_at updated_at], 'user_id'],
    'trips' => [%w[id user_id name started_at ended_at last_recalculated_at distance created_at updated_at], 'user_id']
  }.freeze

  module_function

  def write?
    ENV['WRITE_PHOENIX_FIXTURES'] == '1'
  end

  def read(name)
    JSON.parse(DIR.join(name).read)
  end

  def write(name, data)
    FileUtils.mkdir_p(DIR)
    DIR.join(name).write("#{Oj.dump(data, mode: :strict, float_precision: 0, indent: 2)}\n")
  end

  def normalized(data)
    JSON.parse(Oj.dump(data, mode: :strict, float_precision: 0))
  end

  def boot!
    ActionCable.server.config.cable = { 'adapter' => 'redis', 'url' => ENV.fetch('REDIS_URL'), 'driver' => 'ruby',
                                        'channel_prefix' => PREFIX }.with_indifferent_access
    ActionCable.server.restart
    server = Puma::Server.new(Rails.application, nil, min_threads: 1, max_threads: 8,
                                                      log_writer: Puma::LogWriter.null)
    server.add_tcp_listener('127.0.0.1', 0)
    server.run
    server
  end

  def capture
    queue = Queue.new
    ready = Queue.new
    thread = Thread.new do
      Redis.new(url: ENV.fetch('REDIS_URL'), driver: :ruby).psubscribe("#{PREFIX}:*") do |on|
        on.psubscribe { ready << true }
        on.pmessage { |_pattern, channel, payload| queue << [channel.delete_prefix("#{PREFIX}:"), payload] }
      end
    end
    ready.pop(timeout: 5) || raise('capture did not subscribe')
    [queue, thread]
  end

  def drain(queue, count, seconds = 2)
    Array.new(count) { queue.pop(timeout: seconds) || raise("expected #{count} publishes") }
  end

  def request(method, path, headers)
    lines = ["#{method} #{path} HTTP/1.1", "Host: #{HOST}", *headers.map { |name, value| "#{name}: #{value}" }]
    "#{lines.join("\r\n")}\r\n\r\n"
  end

  def headers(overrides = {})
    names = overrides.keys.map(&:downcase)
    kept = UPGRADE.reject { |name, _| names.include?(name.downcase) }
    kept + overrides.filter_map { |name, value| [name, value] unless value.nil? }
  end

  def tag(value)
    case value
    when Hash then { 'object' => value.map { |key, inner| [key.to_s, tag(inner)] } }
    when Array then value.map { |inner| tag(inner) }
    when Float then { 'float' => value.to_s }
    else value
    end
  end

  def phoenix_redis_url
    ENV.fetch('PHOENIX_TEST_REDIS_URL') { URI(ENV.fetch('REDIS_URL')).tap { |uri| uri.path = '/1' }.to_s }
  end

  def phoenix(code)
    env = { 'MIX_ENV' => 'test', 'PATH' => "#{Dir.home}/.asdf/shims:#{ENV.fetch('PATH')}",
            'PHOENIX_TEST_REDIS_URL' => phoenix_redis_url, 'DATABASE_HOST' => '127.0.0.1' }
    out, status = Open3.capture2e(env, 'mix', 'run', '--no-start', '-e', code,
                                  chdir: Rails.root.join('app-phoenix').to_s)
    raise out unless status.success?

    JSON.parse(out.lines.last)
  end

  def set_cookie(response, name)
    Array(response.headers['Set-Cookie']).flat_map { |line| line.split("\n") }
                                         .find { |line| line.start_with?("#{name}=") }
                                         &.split(';')&.first&.delete_prefix("#{name}=")
  end

  def user_ids = [COOKIES['user']['id'], *IDS.values_at('bob', 'carol', 'dave', 'erin', 'frank')]

  def rows
    ROWS.to_h do |table, (columns, key)|
      result = ActiveRecord::Base.connection.select_all(
        "SELECT #{columns.join(', ')} FROM #{table} WHERE #{key} IN (#{user_ids.join(', ')}) ORDER BY id"
      )
      [table, result.cast_values.map { |values| result.columns.zip(values.map { |v| row_value(v) }).to_h }]
    end
  end

  def row_value(value)
    value.respond_to?(:utc) ? value.utc.iso8601(6) : value
  end

  def identifier(params) = JSON.generate(params)
  def subscribe(params) = JSON.generate(command: 'subscribe', identifier: identifier(params))
  def unsubscribe(params) = JSON.generate(command: 'unsubscribe', identifier: identifier(params))

  class Steps
    attr_reader :entry, :client

    def initialize(entry, client, producer)
      @entry = entry
      @client = client
      @producer = producer
    end

    def observe
      frames = client.frames
      entry['steps'].concat(frames.empty? ? [{ 'silent_ms' => (QUIET * 1000).to_i }] : frames.map { |f| step(f) })
      frames
    end

    def text(data)
      entry['steps'] << { 'send' => data }
      client.text(data)
      observe
    end

    def binary(data)
      entry['steps'] << { 'send_binary' => Base64.strict_encode64(data) }
      client.binary(data)
      observe
    end

    def produce(broadcasting, meta = {}, &)
      @producer.call(entry, broadcasting, meta, &)
      observe
    end

    private

    def step(frame) = frame.is_a?(Hash) ? frame : { 'expect' => frame }
  end

  class Client
    attr_reader :status, :head, :protocol, :content_type, :body

    def initialize(port, request)
      @socket = TCPSocket.new('127.0.0.1', port)
      @socket.write(request)
      @head, rest = read_head
      @status = @head[%r{\AHTTP/1\.[01] (\d{3})}, 1].to_i
      @protocol = header('sec-websocket-protocol')
      @content_type = header('content-type')
      @incoming = WebSocket::Frame::Incoming::Client.new(version: 13)
      if @status == 101
        @incoming << rest
      else
        @body = read_body(rest)
      end
    end

    def text(data)
      @socket.write(WebSocket::Frame::Outgoing::Client.new(version: 13, data: data, type: :text).to_s)
    end

    def binary(data)
      @socket.write(WebSocket::Frame::Outgoing::Client.new(version: 13, data: data, type: :binary).to_s)
    end

    def frames(seconds = QUIET, pings: false)
      out = []
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      loop do
        while (frame = @incoming.next)
          next if frame.type == :ping
          return out << { 'close' => frame.code } if frame.type == :close

          data = String.new(frame.data.to_s, encoding: Encoding::UTF_8)
          out << data if pings || !data.start_with?('{"type":"ping"')
        end
        left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        break if left <= 0 || !@socket.wait_readable(left)

        chunk = @socket.read_nonblock(65_536, exception: false)
        break if chunk.nil?

        @incoming << chunk unless chunk == :wait_readable
      end
      out
    end

    def close
      @socket.close
    end

    private

    def header(name)
      @head[/^#{name}: *(.+?)\r?$/i, 1]
    end

    def read_head
      buffer = +''
      buffer << @socket.readpartial(65_536) until buffer.include?("\r\n\r\n")
      buffer.split("\r\n\r\n", 2)
    end

    def read_body(rest)
      length = header('content-length').to_i
      rest << @socket.readpartial(65_536) while rest.bytesize < length
      rest.byteslice(0, length)
    end
  end
end
