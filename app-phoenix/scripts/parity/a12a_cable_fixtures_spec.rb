# frozen_string_literal: true

require 'rails_helper'
require_relative 'a12a_fixture_support'

RSpec.describe 'Phoenix fixture: A12a ActionCable corpus', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  self.use_transactional_tests = false

  def fx = A12aFixtureSupport
  def ids = fx::IDS
  def shares = fx::SHARES

  before(:all) do
    @previous_cable = ActionCable.server.config.cable
    @puma = A12aFixtureSupport.boot!
    @port = @puma.connected_ports.first
  end

  after(:all) do
    @puma&.stop(true)
    ActionCable.server.config.cable = @previous_cable
    ActionCable.server.restart
  end

  def cleanup!
    users = User.unscoped.where(id: fx.user_ids)
                .or(User.unscoped.where(email: fx::COOKIES['user']['email']))
                .or(User.unscoped.where('email LIKE ?', 'a12a-%@dawarich.test'))
    ids = users.pluck(:id)
    Family::Membership.where(user_id: ids).delete_all
    Family.where(creator_id: ids).delete_all
    User.unscoped.where(id: ids).update_all(deleted_at: nil)
    User.where(id: ids).find_each { |user| Users::Destroy.new(user).call }
  end

  def user!(name, id = ids.fetch(name), email = "a12a-#{name}@dawarich.test")
    create(:user, id: id, email: email, password: fx::PASSWORD, password_confirmation: fx::PASSWORD).tap do |user|
      user.update_columns(encrypted_password: fx::COOKIES['user']['encrypted_password'])
    end
  end

  def sign_in!(user, remember: false)
    reset!
    post user_session_path, params: { user: { email: user.email, password: fx::PASSWORD,
                                              remember_me: remember ? '1' : '0' } }
    expect(response).to have_http_status(:redirect)
    [fx.set_cookie(response, '_dawarich_session'), fx.set_cookie(response, 'remember_user_token')]
  end

  def share!(name, user, **attrs)
    create(:shared_link, id: shares.fetch(name), user: user, resource_type: :live, autobuild_trip: false,
                         name: "A12a #{name}", settings: SharedLink.default_settings_for(:live), **attrs)
  end

  def unlock_cookie(share)
    jar = ActionDispatch::Request.new(Rails.application.env_config.merge('HTTP_HOST' => fx::HOST)).cookie_jar
    jar.encrypted["shared_link_#{share.id}"] = { value: share.unlock_token, expires: 30.days.from_now,
                                                 httponly: true, same_site: :lax }
    { 'cookie' => "shared_link_#{share.id}", 'value' => Rack::Utils.escape(jar["shared_link_#{share.id}"]) }
  end

  def setup!
    alice = user!('alice', fx::COOKIES['user']['id'], fx::COOKIES['user']['email'])
    alice.update_columns(settings: alice.settings.merge('live_map_enabled' => true))
    bob, carol, dave, erin, frank = %w[bob carol dave erin frank].map { |name| user!(name) }
    alice_session, alice_remember = sign_in!(alice, remember: true)
    @sessions = { 'alice' => { 'cookie' => '_dawarich_session', 'value' => alice_session },
                  'alice_remember_only' => { 'cookie' => 'remember_user_token', 'value' => alice_remember } }
    { 'bob' => bob, 'dave_locked' => dave, 'erin_deleted' => erin, 'frank_stale_salt' => frank }.each do |name, user|
      @sessions[name] = { 'cookie' => '_dawarich_session', 'value' => sign_in!(user).first }
    end
    dave.update_columns(locked_at: Time.current)
    frank.update_columns(encrypted_password: fx::COOKIES['other_user']['encrypted_password'])
    bob.update_columns(plan: User.plans[:family], active_until: 1.day.ago)
    family = Family.create!(id: ids['family'], name: 'A12a family', creator: bob)
    Family::Membership.create!(id: ids['owner_membership'], family: family, user: bob, role: :owner)
    Family::Membership.create!(id: ids['member_membership'], family: family, user: carol, role: :member)

    share!('live_open', alice)
    phrase = share!('live_phrase', alice, magic_phrase: fx::PHRASE)
    share!('live_expired', alice).update_columns(expires_at: 1.hour.ago)
    share!('live_revoked', alice).update_columns(revoked_at: 1.hour.ago)
    share!('timeline', alice).update_columns(resource_type: SharedLink.resource_types[:timeline])
    @sessions['share_unlocked'] = unlock_cookie(phrase)

    create(:notification, id: ids['alice_notification'], user: alice, kind: :warning,
                          title: %(<b>Ready</b> & "done" 'ok'), content: 'A12a content')
    create(:notification, id: ids['erin_notification'], user: erin, title: 'A12a erin', content: 'A12a content')
    erin.update_columns(deleted_at: Time.current)
    Notification.insert_all(Array.new(100) do |i|
      { id: ids['bob_notifications'] + i, user_id: bob.id, title: "A12a #{i}", content: 'A12a content', kind: 0,
        created_at: Time.current, updated_at: Time.current }
    end)
    create(:trip, id: ids['trip_idle'], user: alice, name: 'A12a idle', last_recalculated_at: nil)
    create(:trip, id: ids['trip_cooling'], user: alice, name: 'A12a cooling', last_recalculated_at: 30.seconds.ago)
    @alice = alice.reload
    @bob = bob.reload
  end

  def cookie_header(names)
    names.map { |name| "#{@sessions.dig(name, 'cookie')}=#{@sessions.dig(name, 'value')}" }.join('; ')
  end

  def record(name, section, path: '/cable', cookies: [], headers: fx.headers, verb: 'GET')
    sent = cookies.empty? ? headers : headers + [['Cookie', cookie_header(cookies)]]
    client = fx::Client.new(@port, fx.request(verb, path, sent))
    entry = { 'name' => name, 'section' => section, 'method' => verb, 'path' => path, 'headers' => headers,
              'cookies' => cookies, 'status' => client.status, 'protocol' => client.protocol,
              'content_type' => client.content_type, 'body' => client.body, 'steps' => [] }
    @cases << entry
    return entry unless client.status == 101

    steps = fx::Steps.new(entry, client, method(:publish))
    steps.observe
    yield steps if block_given?
    entry
  ensure
    client&.close
  end

  def publish(entry, broadcasting, meta)
    @queue.clear
    @calls.clear
    yield
    published = fx.drain(@queue, @calls.size)
    @calls.zip(published).each do |(name, message), (channel, payload)|
      raise "publish order: #{name} vs #{channel}" unless channel == name
      next unless name == broadcasting
      raise "encoding differs for #{name}" unless ActiveSupport::JSON.encode(message) == payload

      entry['steps'] << { 'publish' => { 'broadcasting' => name, 'payload' => payload } }
      @producers << { 'name' => entry['name'], 'channel' => meta[:channel], 'streamables' => meta[:streamables],
                      'input' => fx.tag(message.as_json), 'broadcasting' => name, 'payload' => payload }
    end
  end

  def share_path(name) = "/cable?share_id=#{shares.fetch(name)}"
  def points = { channel: 'PointsChannel' }
  def signed(*parts) = Turbo::StreamsChannel.signed_stream_name(parts.size == 1 ? parts.first : parts)
  def turbo(parts) = { channel: 'Turbo::StreamsChannel', signed_stream_name: signed(*parts) }
  def user_streamables(user) = [['user', user.id]]
  def points_meta = { channel: 'points', streamables: user_streamables(@alice) }

  def handshake_cases
    upgrade = fx.headers
    record('plain_get', 'handshake', headers: [['Origin', fx::ORIGIN]])
    record('post', 'handshake', verb: 'POST', headers: upgrade + [%w[Content-Length 0]])
    record('origin_missing', 'handshake', headers: fx.headers('Origin' => nil))
    record('origin_other_host', 'handshake', headers: fx.headers('Origin' => 'http://other.example'))
    record('origin_same_host', 'handshake')
    record('origin_https_forwarded', 'handshake',
           headers: fx.headers('Origin' => "https://#{fx::HOST}", 'X-Forwarded-Proto' => 'https'))
    record('origin_localhost_test_env', 'handshake', headers: fx.headers('Origin' => 'http://localhost:3000'))
    ActionCable.server.config.allowed_request_origins = %r{https?://localhost:\d+}
    record('origin_localhost_development', 'handshake', headers: fx.headers('Origin' => 'http://localhost:3000'))
    ActionCable.server.config.allowed_request_origins = nil
    record('protocols_v1_first', 'handshake')
    record('protocols_unsupported_only', 'handshake',
           headers: fx.headers('Sec-WebSocket-Protocol' => 'actioncable-unsupported'))
    record('protocols_none', 'handshake', headers: fx.headers('Sec-WebSocket-Protocol' => nil))
    record('protocols_unknown', 'handshake', headers: fx.headers('Sec-WebSocket-Protocol' => 'graphql-ws'))
    record('version_8', 'handshake', headers: fx.headers('Sec-WebSocket-Version' => '8'))
  end

  def connect_cases
    open = shares['live_open']
    record('user', 'connect', cookies: ['alice'])
    record('anonymous', 'connect')
    record('remember_only', 'connect', cookies: ['alice_remember_only'])
    record('stale_salt', 'connect', cookies: ['frank_stale_salt'])
    record('deleted_user', 'connect', cookies: ['erin_deleted'])
    record('locked_user', 'connect', cookies: ['dave_locked'])
    record('locked_user_with_share', 'connect', path: share_path('live_open'), cookies: ['dave_locked'])
    record('share_open', 'connect', path: share_path('live_open'))
    record('share_open_upper', 'connect', path: "/cable?share_id=#{open.upcase}")
    record('share_open_braces', 'connect', path: "/cable?share_id=%7B#{open}%7D")
    record('share_open_hyphenless', 'connect', path: "/cable?share_id=#{open.delete('-')}")
    record('share_open_blank', 'connect', path: '/cable?share_id=%20')
    record('share_phrase_no_cookie', 'connect', path: share_path('live_phrase'))
    record('share_phrase_cookie', 'connect', path: share_path('live_phrase'), cookies: ['share_unlocked'])
    record('share_expired', 'connect', path: share_path('live_expired'))
    record('share_revoked', 'connect', path: share_path('live_revoked'))
    record('share_timeline', 'connect', path: share_path('timeline'))
    record('share_invalid_uuid', 'connect', path: '/cable?share_id=not-a-uuid')
    record('share_list', 'connect', path: "/cable?share_id%5B%5D=#{open}")
    record('share_hash', 'connect', path: "/cable?share_id%5Bk%5D=#{open}")
    record('query_bad_encoding', 'connect', path: '/cable?share_id=%ZZ')
    record('user_and_share', 'connect', path: share_path('live_open'), cookies: ['alice'])
  end

  def subscribe_one(name, params, cookies: ['alice'], path: '/cable')
    record(name, 'subscribe', cookies: cookies, path: path) { |s| s.text(fx.subscribe(params)) }
  end

  def subscribe_cases
    { 'points_user' => 'PointsChannel', 'tracks_user' => 'TracksChannel', 'imports_user' => 'ImportsChannel',
      'map_edits_user' => 'MapEditsChannel' }.each { |name, channel| subscribe_one(name, { channel: channel }) }
    subscribe_one('points_share_only', points, cookies: [], path: share_path('live_open'))
    subscribe_one('family_member', { channel: 'FamilyLocationsChannel' }, cookies: ['bob'])
    subscribe_one('family_none', { channel: 'FamilyLocationsChannel' })
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    subscribe_one('family_cloud_lapsed', { channel: 'FamilyLocationsChannel' }, cookies: ['bob'])
    allow(DawarichSettings).to receive(:self_hosted?).and_call_original
    shared = { channel: 'SharedLocationChannel', share_id: shares['live_open'] }
    subscribe_one('shared_match', shared, cookies: [], path: share_path('live_open'))
    subscribe_one('shared_mismatch', shared.merge(share_id: shares['live_phrase']), cookies: [],
                                                                                    path: share_path('live_open'))
    subscribe_one('shared_numeric', shared.merge(share_id: 1), cookies: [], path: share_path('live_open'))
    subscribe_one('shared_user_only', shared)
    subscribe_one('turbo_valid', turbo([@alice, :notifications]))
    subscribe_one('turbo_tampered', { channel: 'Turbo::StreamsChannel',
                                      signed_stream_name: "#{signed(@alice, :notifications)}0" })
    subscribe_one('turbo_missing', { channel: 'Turbo::StreamsChannel' })
    subscribe_one('turbo_number', { channel: 'Turbo::StreamsChannel', signed_stream_name: 5 })
    subscribe_one('turbo_empty_name', turbo(['']))
    subscribe_one('application_channel', { channel: 'ApplicationCable::Channel' })
    subscribe_one('unknown_channel', { channel: 'NopeChannel' })
    names_case
    record('duplicate', 'subscribe', cookies: ['alice']) { |s| 2.times { s.text(fx.subscribe(points)) } }
    record('identifier_invalid_json', 'subscribe', cookies: ['alice']) do |s|
      s.text(JSON.generate(command: 'subscribe', identifier: '{'))
    end
    record('identifier_array', 'subscribe', cookies: ['alice']) do |s|
      s.text(JSON.generate(command: 'subscribe', identifier: '[1]'))
    end
    subscribe_one('identifier_ampersand', { channel: 'PointsChannel', x: '&' })
  end

  def names_case
    candidates = fx::CHANNELS + fx::CHANNELS.map { |c| "::#{c}" } + fx::CHANNELS.map(&:downcase) +
                 %w[ActionCable::Channel::Base Object]
    @names = { 'resolved' => [], 'unresolved' => [] }
    record('names', 'subscribe', cookies: ['alice']) do |s|
      candidates.each do |name|
        @names[s.text(fx.subscribe({ channel: name })).empty? ? 'unresolved' : 'resolved'] << name
      end
    end
  end

  def commands_cases
    id = fx.identifier(points)
    { 'unknown_command' => JSON.generate(command: 'nope', identifier: id), 'invalid_json' => '{',
      'json_array' => '[1]', 'json_string' => '"subscribe"' }.each do |name, text|
      record(name, 'commands', cookies: ['alice']) { |s| s.text(text) }
    end
    record('binary_frame', 'commands', cookies: ['alice']) { |s| s.binary("\x01\x02") }
    record('unsubscribe_unknown', 'commands', cookies: ['alice']) do |s|
      s.text(fx.unsubscribe({ channel: 'TracksChannel' }))
    end
    record('unsubscribe_then_publish', 'commands', cookies: ['alice']) do |s|
      s.text(fx.subscribe(points))
      s.text(fx.unsubscribe(points))
      s.produce(PointsChannel.broadcasting_for(@alice), points_meta) { PointsChannel.broadcast_to(@alice, ['after']) }
    end
    { 'message_action_subscribed' => 'subscribed', 'message_action_unknown' => 'nope' }.each do |name, action|
      record(name, 'commands', cookies: ['alice']) do |s|
        s.text(fx.subscribe(points))
        s.text(JSON.generate(command: 'message', identifier: id, data: JSON.generate(action: action)))
        s.produce(PointsChannel.broadcasting_for(@alice), points_meta) { PointsChannel.broadcast_to(@alice, ['again']) }
      end
    end
  end

  def message_case(name, params, broadcasting, meta, cookies: ['alice'], path: '/cable', &)
    record(name, 'messages', cookies: cookies, path: path) do |s|
      s.text(fx.subscribe(params))
      s.produce(broadcasting, meta, &)
    end
  end

  def live_inputs(timestamp)
    [[{ 'latitude' => 52.520000000000003, 'longitude' => -0.0, 'timestamp' => timestamp,
        'id' => ids['live_point'] }],
     [{ timestamp: timestamp, battery: -0.0, altitude: 1.0e15, velocity: '0.0' }]]
  end

  def messages_cases
    alice_meta = ->(channel) { { channel: channel, streamables: user_streamables(@alice) } }
    timestamp = Time.current.to_i - 60
    message_case('points_live', points, PointsChannel.broadcasting_for(@alice), alice_meta.call('points')) do
      Points::LiveBroadcaster.new(@alice.id, *live_inputs(timestamp)).call
    end
    message_case('points_model', points, PointsChannel.broadcasting_for(@alice), alice_meta.call('points')) do
      create(:point, id: ids['model_point'], user: @alice, lonlat: 'POINT(-4.0083 5.36)', timestamp: timestamp,
                     battery: 87, altitude: 12, velocity: '1.5', country_name: 'Côte d’Ivoire')
    end
    track = create(:track, id: ids['track'], user: @alice, start_at: 2.hours.ago, end_at: 1.hour.ago,
                           avg_speed: 12.345678901234567)
    tracks = { channel: 'TracksChannel' }
    message_case('tracks_created', tracks, TracksChannel.broadcasting_for(@alice), alice_meta.call('tracks')) do
      track.broadcast_track_update('created')
    end
    message_case('tracks_destroyed', tracks, TracksChannel.broadcasting_for(@alice), alice_meta.call('tracks')) do
      Track.broadcast_destroyed([[track.id, @alice.id]])
    end
    message_case('map_edit', { channel: 'MapEditsChannel' }, MapEditsChannel.broadcasting_for(@alice),
                 alice_meta.call('map_edits')) do
      MapEditsChannel.broadcast_to(@alice, { type: 'point_moved', version: 1,
                                             data: { point: { id: 7, latitude: 52.5, longitude: 13.4 },
                                                     note: "line#{0x2028.chr(Encoding::UTF_8)}break</b>&" } })
    end
    message_case('imports_delete', { channel: 'ImportsChannel' }, ImportsChannel.broadcasting_for(@alice),
                 alice_meta.call('imports')) do
      Imports::DestroyJob.new.send(:broadcast_deletion_complete, Import.new(id: ids['import'], user: @alice))
    end
    family = @bob.family
    message_case('family_location', { channel: 'FamilyLocationsChannel' },
                 FamilyLocationsChannel.broadcasting_for(family),
                 { channel: 'family_locations', streamables: [['family', family.id]] }, cookies: ['bob']) do
      Point.new(id: ids['family_point'], user: @bob, lonlat: 'POINT(13.404954 52.520008)', timestamp: timestamp)
           .send(:broadcast_to_family)
    end
    shared_messages(timestamp)
    turbo_messages
  end

  def shared_messages(timestamp)
    share = SharedLink.find(shares['live_open'])
    params = { channel: 'SharedLocationChannel', share_id: share.id }
    meta = { channel: 'shared_location', streamables: [['shared_link', share.id]] }
    broadcasting = SharedLocationChannel.broadcasting_for(share)
    path = share_path('live_open')
    message_case('shared_point', params, broadcasting, meta, cookies: [], path: path) do
      Points::LiveBroadcaster.new(@alice.id, *live_inputs(timestamp)).call
    end
    message_case('shared_masked', params, broadcasting, meta, cookies: [], path: path) do
      allow_any_instance_of(SharedLinks::LivePoint).to receive(:inside_privacy_zone?).and_return(true)
      Points::LiveBroadcaster.new(@alice.id, *live_inputs(timestamp)).call
      allow_any_instance_of(SharedLinks::LivePoint).to receive(:inside_privacy_zone?).and_call_original
    end
    message_case('shared_revoked', params, broadcasting, meta, cookies: [], path: path) do
      SharedLocationChannel.broadcast_to(share, { revoked: true })
    end
  end

  def turbo_messages
    notifications = Turbo::StreamsChannel.verified_stream_name(signed(@alice, :notifications))
    meta = ->(name) { { channel: nil, streamables: [['user', @alice.id], name] } }
    message_case('turbo_notification', turbo([@alice, :notifications]), notifications, meta.call('notifications')) do
      Notification.find(ids['alice_notification']).broadcast_notification
    end
    posters = Turbo::StreamsChannel.verified_stream_name(signed(@alice, :posters))
    message_case('turbo_poster', turbo([@alice, :posters]), posters, meta.call('posters')) do
      Poster.new(id: ids['poster'], user: @alice, name: 'A12a poster', status: :completed)
            .send(:broadcast_status_change)
    end
  end

  def relay_entry(events, table)
    @queue.clear
    @calls.clear
    events.each do |event|
      columns = event.keys
      values = event.values.map { |v| ActiveRecord::Base.connection.quote(v) }
      ActiveRecord::Base.connection.execute(
        "INSERT INTO phoenix.#{table} (#{columns.join(', ')}, created_at) VALUES (#{values.join(', ')}, now())"
      )
    end
    error = begin
      yield
      nil
    rescue StandardError => e
      e.class.name
    end
    { 'events' => events, 'published' => fx.drain(@queue, @calls.size), 'error' => error }.compact
  end

  def relay_cases
    relay = {}
    locales = []
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to).and_wrap_original do |original, *args, **kw|
      locales << I18n.locale.to_s
      original.call(*args, **kw)
    end
    ActiveRecord::Base.transaction do
      phoenix_tables!
      Notification.insert_all([{ id: ids['bob_last_notification'], user_id: @bob.id, title: 'A12a last',
                                 content: 'A12a content', kind: 2, created_at: Time.current,
                                 updated_at: Time.current }])
      { 'notification_created' => 'alice_notification', 'notification_badge_99_plus' => 'bob_last_notification',
        'notification_soft_deleted_user' => 'erin_notification' }.each do |name, id|
        relay[name] = relay_entry([{ 'notification_id' => ids[id] }], 'notification_events') do
          Notifications::EventsBroadcaster.drain_once
        end
      end
      { 'trip_path' => ['trip_idle', 'path', false], 'trip_finished_ok' => ['trip_idle', 'finished', false],
        'trip_finished_failed' => ['trip_idle', 'finished', true],
        'trip_finished_cooling' => ['trip_cooling', 'finished', false],
        'trip_distance' => ['trip_idle', 'distance', false],
        'trip_countries' => ['trip_idle', 'countries', false] }.each do |name, (trip, kind, failed)|
        event = { 'trip_id' => ids[trip], 'kind' => kind, 'distance_unit' => 'km', 'failed' => failed }
        relay[name] = relay_entry([event], 'trip_events') { Trips::CalculationEventsBroadcaster.drain_once }
      end
      raise ActiveRecord::Rollback
    end
    relay.merge('trip_show_targets' => trip_show_targets, 'relay_locale' => locales.uniq.sole)
  end

  def trip_show_targets
    sign_in!(@alice)
    get trip_path(ids['trip_idle'])
    expect(response).to have_http_status(:ok)
    %w[trip_distance trip_countries].index_with { |target| response.body.include?(%(id="#{target}")) }
  end

  def pings
    client = fx::Client.new(@port, fx.request('GET', '/cable', fx.headers + [['Cookie', cookie_header(['alice'])]]))
    stamps = []
    frames = []
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 7
    while stamps.size < 2 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      client.frames(0.1, pings: true).grep(/\A\{"type":"ping"/).each do |frame|
        frames << frame
        stamps << Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
    { 'sample' => frames.first, 'gap_seconds' => (stamps[1] - stamps[0]).round }
  ensure
    client&.close
  end

  def constants
    Rails.application.eager_load!
    channels = ActionCable::Channel::Base.descendants.sort_by(&:name)
    { 'internal' => ActionCable::INTERNAL.as_json, 'descendants' => channels.map(&:name),
      'channel_names' => channels.to_h { |c| [c.name, c.channel_name] }, 'rails_env' => Rails.env,
      'beat_interval' => ActionCable::Server::Connections::BEAT_INTERVAL }
  end

  def corpus
    @cases = []
    @producers = []
    @calls = []
    @queue, capture = fx.capture
    allow(ActionCable.server).to receive(:broadcast).and_wrap_original do |original, broadcasting, message, **kw|
      @calls << [broadcasting, message]
      original.call(broadcasting, message, **kw)
    end
    handshake_cases
    connect_cases
    subscribe_cases
    commands_cases
    messages_cases
    { 'now' => Time.current.utc.iso8601(6), 'prefix' => fx::PREFIX, 'host' => fx::HOST,
      'users' => { 'alice' => @alice.id }.merge(%w[bob carol dave erin frank].index_with { |n| ids[n] }),
      'shares' => shares, 'families' => { 'bob' => ids['family'] },
      'trips' => ids.slice('trip_idle', 'trip_cooling'), 'sessions' => @sessions, 'rows' => fx.rows,
      'cases' => @cases, 'names' => @names, 'producers' => @producers, 'relay' => relay_cases, 'pings' => pings,
      'constants' => constants }
  ensure
    capture&.kill
  end

  def deterministic(data)
    fx.normalized(data.except('sessions').merge('pings' => data['pings'].except('gap_seconds')))
  end

  it 'writes the cable corpus' do
    travel_to(fx::NOW) do
      cleanup!
      setup!
      data = corpus
      expect(@cases.size).to be >= 80
      expect(@cases.find { |c| c['name'] == 'user' }['steps'].first).to eq('expect' => '{"type":"welcome"}')
      if fx.write?
        fx.write('cable.json', data)
      else
        expect(deterministic(data)).to eq(deterministic(fx.read('cable.json')))
      end
    ensure
      cleanup!
    end
  end
end
