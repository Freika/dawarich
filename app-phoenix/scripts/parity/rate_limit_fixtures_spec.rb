# frozen_string_literal: true

require 'rails_helper'
require_relative 'rate_limit_fixture_support'

RSpec.describe 'Phoenix fixture: rack-attack throttles, blocklist and responders' do
  include ActiveSupport::Testing::TimeHelpers
  include RateLimitFixtureSupport

  let(:normalizer) { Rack::Attack.throttle_discriminator_normalizer }

  around do |example|
    enabled = Rack::Attack.enabled
    store = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    example.run
  ensure
    Rack::Attack.enabled = enabled
    Rack::Attack.cache.store = store
  end

  after { travel_back }

  it 'writes or verifies app-phoenix/test/fixtures/rate_limit/corpus.json' do
    expect(Rails.application.secret_key_base).to eq(RateLimitFixtureSupport::SECRET)
    travel_to(RateLimitFixtureSupport::NOW)
    @stored = RateLimitFixtureSupport.stored
    data = {
      'now' => RateLimitFixtureSupport::NOW.to_i,
      'middleware' => Rails.application.config.middleware.map(&:name),
      'throttles' => throttle_table, 'plan_limits' => Rack::Attack.api_rate_limits,
      'blocklists' => Rack::Attack.blocklists.keys, 'max_json_body' => MAX_JSON_BODY_BYTES,
      'paths' => paths, 'media_types' => media_types, 'ips' => ips, 'params' => param_vectors,
      'normalized' => normalized_vectors, 'present' => present_vectors, 'plans' => plans,
      'scenarios' => scenarios.map { |scenario| play(scenario) },
      'cookies' => @cookies || {}
    }
    write? ? write(data) : expect(normalized(data)).to(eq(@stored))
  end

  def keys = RateLimitFixtureSupport::KEYS
  def at(offset) = RateLimitFixtureSupport::NOW.to_i + offset

  def paths
    ['/users/sign_in', '/users/sign_in/', '//users//sign_in', '/users/sign_in.json', '/users/sign_in.',
     '/s/AbC%2fd/unlock', '/s/abc%2Fd/unlock.json', '/s/a.b/unlock', '/api/v1/points.json', '/admin/flipper/',
     '/s/x%e2%82%ac', '/s/abc', '/api/v1/tiles/points/1/2/3.mvt', '/'].map do |raw|
      path = Rack::Attack::PathNormalizer.normalize_path(raw)
      { 'path' => path, 'raw' => raw,
        'throttle_path' => throttle_path(Rack::Request.new('PATH_INFO' => path, 'SCRIPT_NAME' => '')) }
    end
  end

  def media_types
    ['application/json', 'Application/JSON; charset=utf-8', ' application/json', 'application/json ,text/plain',
     'text/x-json', 'application/jsonrequest', 'application/geo+json', 'application/x-www-form-urlencoded',
     'multipart/form-data; boundary=x', '', 'json', "application/json\t"].map do |type|
      request = Rack::Request.new('CONTENT_TYPE' => type)
      { 'content_type' => type, 'json' => json_request?(request), 'media_type' => request.media_type }
    end
  end

  def ips
    [
      ['203.0.113.9', {}], ['127.0.0.1', {}], ['127.0.0.1', { 'HTTP_X_FORWARDED_FOR' => '203.0.113.9, 10.0.0.2' }],
      ['10.0.0.3', { 'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 203.0.113.9' }],
      ['172.31.0.1', { 'HTTP_X_FORWARDED_FOR' => '10.1.1.1, 192.168.0.1' }],
      ['172.32.0.1', { 'HTTP_X_FORWARDED_FOR' => '203.0.113.9' }], ['::1', { 'HTTP_X_FORWARDED_FOR' => '2001:db8::1' }],
      ['127.0.0.1', { 'HTTP_X_FORWARDED_FOR' => '[2001:db8::2]:443' }],
      ['127.0.0.1', { 'HTTP_X_FORWARDED_FOR' => '203.0.113.9:8080' }],
      ['127.0.0.1', { 'HTTP_X_FORWARDED_FOR' => '<garbage>' }],
      ['127.0.0.1', { 'HTTP_X_FORWARDED_FOR' => ', 203.0.113.7' }],
      ['127.0.0.1', { 'HTTP_X_FORWARDED_FOR' => '203.0.113.7, ' }],
      ['127.0.0.1', { 'HTTP_FORWARDED' => 'for=198.51.100.4;proto=https', 'HTTP_X_FORWARDED_FOR' => '203.0.113.9' }],
      ['127.0.0.1', { 'HTTP_FORWARDED' => 'for="[2001:db8::3]:80", for=10.0.0.9' }],
      ['127.0.0.1', { 'HTTP_FORWARDED' => 'proto=https', 'HTTP_X_FORWARDED_FOR' => '203.0.113.5' }],
      ['fd00::1', { 'HTTP_X_FORWARDED_FOR' => 'FC00::2' }],
      ['10.0.0.1', { 'HTTP_X_FORWARDED_FOR' => '127.0.0.1, 10.0.0.2' }]
    ].map do |remote, extra|
      { 'headers' => extra.to_h { |name, value| [name.delete_prefix('HTTP_').downcase.tr('_', '-'), value] },
        'ip' => Rack::Request.new(extra.merge('REMOTE_ADDR' => remote)).ip, 'remote_addr' => remote }
    end
  end

  def param_vectors
    [
      ['GET', 'api_key=a&api_key=b', nil, '', nil],
      ['POST', 'api_key=q', 'application/x-www-form-urlencoded', 'api_key=f', nil],
      ['POST', 'email=q', 'application/json', '{"email":"j","user":{"email":"u"}}', nil],
      ['POST', 'user%5Bemail%5D=q', 'application/x-www-form-urlencoded', 'user%5Bemail%5D=f&user%5Bpassword%5D=p', nil],
      ['POST', '', nil, 'api_key=n', nil], ['POST', '', 'text/plain', 'api_key=t', nil],
      ['POST', 'a=1', 'application/json', '[1,2]', nil], ['POST', '', 'application/json', '   ', nil],
      ['POST', '', 'application/json', '{"challenge_token":42,"email":false}', nil],
      ['GET', 'share_id=&import_ticket=t+1%21', nil, '', nil],
      ['GET', 'api_key%5B%5D=x', nil, '', %w[params body]],
      ['POST', '', 'application/x-www-form-urlencoded', 'user=a&user%5Bemail%5D=b', %w[params body]],
      ['GET', 'a=%ZZ', nil, '', %w[params body]], ['POST', '', 'application/json', '{bad', %w[body]],
      ['POST', '', 'multipart/form-data; boundary=x', '', %w[params body]]
    ].map do |method, query, type, body, defer|
      env = lambda do
        Rack::MockRequest.env_for('/x', method: method, input: body).tap do |e|
          e['QUERY_STRING'] = query
          e['CONTENT_TYPE'] = type if type
        end
      end
      { 'body' => body, 'content_type' => type, 'defer' => defer, 'method' => method, 'query' => query,
        'safe_body_params' => safe_body_params(Rack::Request.new(env.call)),
        'safe_params' => safe_params(Rack::Request.new(env.call)) }
    end
  end

  def normalized_vectors
    nbsp = 0xa0.chr(Encoding::UTF_8)
    [' Ab ', "\tVictim@Example.INVALID\n", "#{0.chr}x#{0.chr}", [0x3a3, 0x391, 0x3a3].pack('U*'),
     "#{[0x130].pack('U*')}stanbul", [0x1e9e].pack('U*'), "#{nbsp}a#{nbsp}", '', '2001:DB8::1', 42].map do |value|
      { 'input' => value, 'output' => normalizer.call(value) }
    end
  end

  def present_vectors
    ['', ' ', "\t\n", 0x3000.chr(Encoding::UTF_8), 0xa0.chr(Encoding::UTF_8), 'a', nil].map do |value|
      { 'input' => value, 'present' => value.present? }
    end
  end

  def plans
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    specs = [['lite', :lite, nil, nil], ['pro', :pro, nil, nil], ['family', :family, 1.year.from_now, nil],
             ['member', :lite, nil, [:family, 1.year.from_now, nil]],
             ['lapsed', :lite, nil, [:family, 1.year.ago, nil]], ['deleted', :pro, nil, nil],
             ['mixed', :lite, nil, nil]]
    rows = specs.map do |handle, plan, until_at, family|
      user = account(keys.fetch(handle), plan, until_at)
      user.update_columns(deleted_at: Time.current) if handle == 'deleted'
      join_family(user, *family) if family
      { 'active_until' => until_at&.utc&.iso8601, 'deleted' => handle == 'deleted',
        'family' => family && { 'access_until' => family[2]&.utc&.iso8601,
                                'owner_active_until' => family[1].utc.iso8601,
                                'owner_plan' => User.plans.fetch(family[0].to_s) },
        'handle' => handle, 'plan' => User.plans.fetch(plan.to_s), 'value' => user.api_key }
    end
    rows << { 'active_until' => nil, 'deleted' => false, 'family' => nil, 'handle' => 'unknown', 'plan' => nil,
              'value' => keys['unknown'] }
    rows.map { |row| row.merge('effective_plan' => User.find_by(api_key: row['value'])&.effective_plan&.to_s) }
  end

  def account(api_key, plan, active_until)
    create(:user, skip_auto_trial: true).tap do |user|
      user.update_columns(api_key: api_key, plan: User.plans.fetch(plan.to_s), active_until: active_until)
    end
  end

  def join_family(member, owner_plan, owner_until, access_until)
    owner = account("a13cowner#{member.id}qqqqqqqqqq", owner_plan, owner_until)
    family = create(:family, creator: owner, access_until: access_until)
    create(:family_membership, :owner, family: family, user: owner)
    create(:family_membership, family: family, user: member)
  end

  def play(scenario)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(scenario['mode'] == 'self_hosted')
    stub_const('MANAGER_URL', scenario['manager_url'])
    store = RateLimitFixtureSupport::RecordingStore.new
    Rack::Attack.cache.store = store
    scenario.merge('steps' => scenario['steps'].map do |step|
      step['seed'] ? seeded(store, step) : requested(store, step)
    end)
  end

  def seeded(store, step)
    seed = step['seed']
    store.seed("rack::attack:#{step['at'] / seed['period']}:#{seed['throttle']}:#{seed['discriminator']}",
               seed['value'])
    step
  end

  def requested(store, step)
    travel_to(Time.at(step['at']).utc)
    store.calls.clear
    @inner = nil
    env = env_for(step['request'])
    status, headers, body = stack.call(env)
    text = +''
    body.each { |part| text << part }
    body.close if body.respond_to?(:close)
    length = env['CONTENT_LENGTH'] && !step['request']['chunked'] ? [['content-length', env['CONTENT_LENGTH']]] : []
    step.merge('increments' => store.calls.map { |key, ttl| increment(key, ttl) },
               'request' => step['request'].merge('headers' => step['request']['headers'] + length),
               'response' => @inner ? { 'status' => 'passed' } : response(status, headers, text), 'token' => token)
  end

  def stack
    @stack ||= Rails.application.config.middleware.build(lambda do |env|
      @inner = env
      [200, { 'content-type' => 'text/plain' }, ['passed']]
    end)
  end

  def env_for(request)
    query = request['query'].to_s
    uri = "http://#{RateLimitFixtureSupport::HOST}#{request['path']}#{"?#{query}" unless query.empty?}"
    env = Rack::MockRequest.env_for(uri, method: request['method'], input: request['body'].to_s,
                                         'REMOTE_ADDR' => request['remote_addr']).merge!(Rails.application.env_config)
    request['headers'].each { |name, value| env[cgi_name(name)] = value }
    env.delete('CONTENT_LENGTH') if request['chunked']
    env
  end

  def cgi_name(name)
    return 'CONTENT_TYPE' if name == 'content-type'
    return 'CONTENT_LENGTH' if name == 'content-length'

    "HTTP_#{name.upcase.tr('-', '_')}"
  end

  def increment(key, ttl)
    window, name, discriminator = key.delete_prefix('rack::attack:').split(':', 3)
    { 'discriminator' => discriminator, 'throttle' => name, 'ttl' => ttl, 'window' => window.to_i }
  end

  def response(status, headers, text)
    raise "Rails answered #{status}: #{text[0, 200]}" unless [413, 429].include?(status)

    pairs = headers.to_a.map { |name, value| [name.downcase, value] }
    recorded = pairs.select { |name, _| RateLimitFixtureSupport::NAMES.include?(name) }
    { 'body' => text, 'header_names' => pairs.map(&:first).sort,
      'headers' => recorded.group_by(&:first).transform_values do |list|
        list.map(&:last)
      end.sort.to_h, 'status' => status }
  end

  def token
    data = @inner&.dig('rack.attack.throttle_data', 'api/token')
    data && { 'count' => data[:count], 'limit' => data[:limit], 'period' => data[:period] }
  end

  def step(method, path, offset: 0, ip: '203.0.113.10', query: '', headers: [], body: '', type: nil,
           chunked: false, phoenix: nil)
    headers += [['content-type', type]] if type
    headers += [%w[transfer-encoding chunked]] if chunked
    { 'at' => at(offset), 'phoenix' => phoenix,
      'request' => { 'body' => body, 'chunked' => chunked, 'headers' => headers, 'method' => method, 'path' => path,
                     'query' => query, 'remote_addr' => ip } }.compact
  end

  def seed(throttle, discriminator, period, value, offset: 0)
    { 'at' => at(offset), 'seed' => { 'discriminator' => normalizer.call(discriminator), 'period' => period,
                                      'throttle' => throttle, 'value' => value } }
  end

  def bearer(handle) = [['authorization', "Bearer #{keys.fetch(handle)}"]]
  def form_body(text) = { type: 'application/x-www-form-urlencoded', body: text }
  def json_body(value) = { type: 'application/json', body: value.to_json }

  def padded(bytes)
    base = { 'user' => { 'email' => 'pad@example.invalid' }, 'pad' => '' }.to_json.bytesize
    json_body('user' => { 'email' => 'pad@example.invalid' }, 'pad' => 'x' * (bytes - base))
  end

  def cookie(name)
    @cookies ||= {}
    @cookies[name] ||= session_cookie(name, @stored.fetch('cookies', {}))
    [['cookie', "_dawarich_session=#{@cookies[name]}"]]
  end

  def scenario(name, mode, steps, manager_url: 'https://manager.example')
    { 'manager_url' => manager_url, 'mode' => mode, 'name' => name, 'steps' => steps }
  end

  def scenarios
    [
      scenario('api_token', 'cloud', api_token_steps), scenario('tiles', 'cloud', tiles_steps),
      scenario('points_creation', 'cloud', points_creation_steps),
      scenario('heavy_recompute', 'cloud', heavy_recompute_steps, manager_url: nil),
      scenario('oversized_cloud', 'cloud', oversized_steps('cloud')),
      scenario('oversized_self_hosted', 'self_hosted', oversized_steps('self_hosted'), manager_url: nil),
      scenario('logins_web', 'cloud', logins_web_steps, manager_url: 'https://manager.example/a&b'),
      scenario('logins_api', 'cloud', logins_api_steps), scenario('signups', 'cloud', signups_steps),
      scenario('oauth', 'cloud', oauth_steps), scenario('users_exist', 'cloud', users_exist_steps),
      scenario('otp_api', 'cloud', otp_api_steps), scenario('otp_web', 'cloud', otp_web_steps),
      scenario('account_link_cloud', 'cloud', account_link_steps),
      scenario('account_link_self_hosted', 'self_hosted', account_link_steps, manager_url: nil),
      scenario('two_factor', 'cloud', two_factor_steps), scenario('trial_welcome', 'cloud', trial_welcome_steps),
      scenario('admin_flipper', 'cloud', admin_flipper_steps),
      scenario('shared_viewer_and_cable', 'cloud', shared_viewer_and_cable_steps),
      scenario('unlock_self_hosted', 'self_hosted', unlock_steps, manager_url: nil),
      scenario('unlock_cloud', 'cloud', unlock_steps), scenario('pending_imports', 'cloud', pending_imports_steps),
      scenario('import_claim', 'cloud', import_claim_steps),
      scenario('self_hosted_exempt', 'self_hosted', self_hosted_exempt_steps, manager_url: nil),
      scenario('deferrals', 'cloud', deferral_steps)
    ]
  end

  def api_token_steps
    [
      seed('api/token', keys['lite'], 3600, 199),
      *Array.new(2) { step('GET', '/api/v1/points', headers: bearer('lite')) },
      seed('api/token', keys['pro'], 3600, 999),
      *Array.new(2) { step('GET', '/api/v1/points', headers: bearer('pro')) },
      *%w[family member lapsed deleted unknown mixed].map { |h| step('GET', '/api/v1/stats', headers: bearer(h)) },
      step('GET', '/api/v1/stats', query: "api_key=#{keys['family']}", headers: bearer('lite')),
      step('GET', '/api/v1/stats', query: 'api_key=', headers: bearer('lite')),
      step('POST', '/api/v1/visits', query: "api_key=#{keys['lite']}", **form_body("api_key=#{keys['family']}")),
      step('POST', '/api/v1/visits', **json_body('api_key' => keys['family'])),
      step('HEAD', '/api/v1/stats', headers: bearer('family')),
      step('GET', '/api/v1/stats/', headers: bearer('family'))
    ]
  end

  def tiles_steps
    [
      seed('api/tiles_burst', "tiles_burst:#{keys['pro']}", 30, 599),
      step('GET', '/api/v1/tiles/points/1/2/3.mvt', headers: bearer('pro')),
      step('GET', '/api/v1/tiles/tracks/1/2/3.mvt', headers: bearer('pro')),
      seed('api/tiles', "tiles:#{keys['lite']}", 3600, 9_999),
      *Array.new(2) { step('GET', '/api/v1/tiles/points/1/2/3.mvt', headers: bearer('lite')) },
      step('GET', '/api/v1/tiles/points/1/2/3.mvt', offset: 30, headers: bearer('pro'))
    ]
  end

  def points_creation_steps
    paths = %w[/api/v1/points /api/v1/points.json /api/v1/owntracks/points /api/v1/overland/batches
               /api/v1/traccar/points]
    [
      *paths.map { |path| step('POST', path, headers: bearer('pro'), **json_body({})) },
      seed('api/points_creation', "points_creation:#{keys['family']}", 3600, 9_999),
      *Array.new(2) { step('POST', '/api/v1/points', headers: bearer('family'), **json_body({})) }
    ]
  end

  def heavy_recompute_steps
    [
      *Array.new(6) { step('POST', '/api/v1/recalculations', headers: bearer('pro')) },
      step('POST', '/api/v1/points/reapply_anomaly_filter', headers: bearer('family'))
    ]
  end

  def logins_web_steps
    emails = [' Victim@Example.INVALID ', 'victim@example.invalid', 'VICTIM@example.invalid',
              "victim@example.invalid\t", 'Victim@example.invalid', 'victim@EXAMPLE.invalid']
    json = json_body('user' => { 'email' => 'json@example.invalid' })
    [
      *emails.each_with_index.map do |email, i|
        step('POST', '/users/sign_in', ip: "203.0.113.#{20 + i}",
                                       **form_body("user%5Bemail%5D=#{CGI.escape(email)}&user%5Bpassword%5D=x"))
      end,
      step('POST', '/users/sign_in', ip: '203.0.113.30', **json),
      step('POST', '/users/sign_in', ip: '203.0.113.31', query: 'user%5Bemail%5D=query%40example.invalid',
                                     **form_body('user%5Bemail%5D=form%40example.invalid')),
      step('POST', '/users/sign_in.json', ip: '203.0.113.32', **json),
      step('POST', '/users//sign_in/', ip: '203.0.113.33', **json),
      step('POST', '/users/sign_in', ip: '203.0.113.34', **json_body('user' => { 'email' => 42 })),
      step('POST', '/users/sign_in', ip: '203.0.113.35', **json_body('user' => 'x')),
      step('POST', '/users/sign_in', ip: '203.0.113.36', **form_body('user%5Bemail%5D=')),
      seed('logins/ip', '203.0.113.40', 60, 19),
      step('POST', '/users/sign_in', ip: '203.0.113.40', **form_body('user%5Bemail%5D=a%40example.invalid')),
      step('POST', '/users/sign_in', ip: '203.0.113.40', **form_body('user%5Bemail%5D=d%40example.invalid'))
    ]
  end

  def logins_api_steps
    [
      *Array.new(6) do |i|
        step('POST', '/api/v1/auth/login', ip: "203.0.113.#{50 + i}", **json_body('email' => ' A@Example.Invalid '))
      end,
      step('POST', '/api/v1/auth/login', ip: '203.0.113.60', **json_body('email' => false)),
      step('POST', '/api/v1/auth/login', ip: '203.0.113.61', phoenix: 'defer', **json_body('email' => { 'x' => 1 })),
      step('POST', '/api/v1/auth/login', ip: '203.0.113.62', query: 'email=q%40example.invalid',
                                         **json_body('email' => 'j@example.invalid'))
    ]
  end

  def signups_steps
    [
      *Array.new(6) { step('POST', '/users', ip: '203.0.113.70') },
      seed('signups/ip_hourly', '203.0.113.71', 3600, 19),
      *Array.new(2) { step('POST', '/users', ip: '203.0.113.71') },
      *Array.new(6) { step('POST', '/api/v1/auth/register', ip: '203.0.113.72', **json_body({})) },
      step('POST', '/users.json', ip: '203.0.113.73')
    ]
  end

  def oauth_steps
    [
      seed('oauth/token_exchange', '203.0.113.80', 60, 29),
      step('POST', '/api/v1/auth/apple', ip: '203.0.113.80', **json_body({})),
      step('POST', '/api/v1/auth/google', ip: '203.0.113.80', **json_body({})),
      seed('apple_web_callback_per_ip', '203.0.113.81', 60, 19),
      *Array.new(2) { step('POST', '/users/auth/apple/callback', ip: '203.0.113.81', **form_body('state=s')) }
    ]
  end

  def users_exist_steps
    webhook = [['x-webhook-secret', RateLimitFixtureSupport::WEBHOOK]]
    [
      seed('users/exist', Digest::SHA256.hexdigest(RateLimitFixtureSupport::WEBHOOK)[0, 32], 3600, 599),
      *Array.new(2) { step('POST', '/api/v1/users/exist', headers: webhook, **json_body({})) },
      step('POST', '/api/v1/users/exist', **json_body({})),
      step('POST', '/api/v1/users/exist', headers: [['x-webhook-secret', '   ']], **json_body({}))
    ]
  end

  def otp_api_steps
    token = json_body('challenge_token' => RateLimitFixtureSupport::CHALLENGE)
    second = json_body('challenge_token' => "#{RateLimitFixtureSupport::CHALLENGE}2")
    [
      *Array.new(6) { step('POST', '/api/v1/auth/otp_challenge', ip: '203.0.113.90', **token) },
      *%w[203.0.113.91 203.0.113.92].flat_map do |ip|
        Array.new(3) { step('POST', '/api/v1/auth/otp_challenge', ip: ip, **second) }
      end,
      step('POST', '/api/v1/auth/otp_challenge', ip: '203.0.113.93', **json_body('challenge_token' => 42)),
      step('POST', '/api/v1/auth/otp_challenge', ip: '203.0.113.94', **json_body({}))
    ]
  end

  def otp_web_steps
    [
      *Array.new(6) do |i|
        step('POST', '/users/otp_challenge', ip: "203.0.113.#{100 + i}", headers: cookie('otp'),
                                             **form_body('otp_attempt=000000'))
      end,
      step('POST', '/users/otp_challenge', ip: '203.0.113.110', **form_body('otp_attempt=000000')),
      step('POST', '/users/otp_challenge', ip: '203.0.113.111', headers: cookie('otp_blank')),
      step('POST', '/users/otp_challenge', ip: '203.0.113.112', headers: cookie('otp_false'))
    ]
  end

  def two_factor_steps
    [
      *Array.new(5) { step('POST', '/api/v1/users/me/two_factor/confirm', headers: bearer('pro')) },
      step('DELETE', '/api/v1/users/me/two_factor.json', headers: bearer('pro')),
      step('GET', '/api/v1/users/me/two_factor/setup', headers: bearer('family'))
    ]
  end

  def trial_welcome_steps
    [
      seed('trial/welcome', '203.0.113.140', 60, 29),
      step('GET', '/trial/welcome', ip: '203.0.113.140'), step('HEAD', '/trial/welcome', ip: '203.0.113.140'),
      step('GET', '/trial/welcome', ip: '203.0.113.140')
    ]
  end

  def admin_flipper_steps
    [
      seed('admin/flipper', '203.0.113.141', 300, 29),
      step('GET', '/admin/flipper', ip: '203.0.113.141'),
      step('POST', '/admin/flipper/features', ip: '203.0.113.141', **form_body('name=x'))
    ]
  end

  def shared_viewer_and_cable_steps
    [
      seed('shared_links/viewer', '203.0.113.142', 60, 119),
      step('GET', '/s/abc', ip: '203.0.113.142'), step('GET', '/api/v1/shared/locations', ip: '203.0.113.142'),
      step('GET', '/s/abc.json', ip: '203.0.113.143'),
      step('GET', '/cable', ip: '203.0.113.144', query: 'share_id=s1'),
      step('GET', '/cable', ip: '203.0.113.144'),
      step('GET', '/cable', ip: '203.0.113.144', query: 'share_id=')
    ]
  end

  def pending_imports_steps
    multipart = "--a13c\r\nContent-Disposition: form-data; name=\"api_key\"\r\n\r\n#{keys['family']}\r\n--a13c--\r\n"
    [
      seed('api/v1/imports/pending CREATE', '203.0.113.160', 3600, 59),
      *Array.new(2) { step('POST', '/api/v1/imports/pending', ip: '203.0.113.160', phoenix: 'defer', **json_body({})) },
      step('POST', '/api/v1/imports/pending', ip: '203.0.113.161', phoenix: 'defer',
                                              type: 'multipart/form-data; boundary=a13c', body: multipart)
    ]
  end

  def import_claim_steps
    [
      seed('imports/claim attempts', '203.0.113.170', 3600, 29),
      *Array.new(2) { step('GET', '/users/sign_up', ip: '203.0.113.170', query: 'import_ticket=t1') },
      step('GET', '/users/sign_up', ip: '203.0.113.171', query: 'import_ticket='),
      step('GET', '/users/sign_up', ip: '203.0.113.171')
    ]
  end

  def self_hosted_exempt_steps
    [
      step('GET', '/api/v1/points', headers: bearer('pro')),
      step('GET', '/api/v1/tiles/points/1/2/3.mvt', headers: bearer('pro')),
      step('POST', '/api/v1/points', headers: bearer('pro'), **json_body({})),
      step('POST', '/users/sign_in', **form_body('user%5Bemail%5D=a%40example.invalid')),
      step('POST', '/api/v1/auth/login', **json_body('email' => 'a@example.invalid')),
      step('POST', '/users'), step('GET', '/trial/welcome'), step('GET', '/admin/flipper'),
      step('GET', '/s/abc'), step('POST', '/api/v1/imports/pending', phoenix: 'defer', **json_body({})),
      step('GET', '/users/sign_up', query: 'import_ticket=t'),
      step('POST', '/users/otp_challenge', headers: cookie('otp'))
    ]
  end

  def deferral_steps
    form = form_body('user%5Bemail%5D=m%40example.invalid')
    [
      step('POST', '/users/sign_in', ip: '203.0.113.180', phoenix: 'defer',
                                     **form_body('_method=put&user%5Bemail%5D=m%40example.invalid')),
      step('POST', '/users/sign_in', ip: '203.0.113.181', phoenix: 'defer',
                                     headers: [%w[x-http-method-override PUT]], **form),
      step('POST', '/users/sign_in', ip: '203.0.113.182', phoenix: 'defer', headers: [%w[x_custom 1]], **form),
      step('GET', '/api/v1/stats', phoenix: 'defer', query: 'api_key%5B%5D=x')
    ]
  end

  def oversized_steps(mode)
    [
      step('POST', '/users/sign_in', **padded(16_385)),
      step('POST', '/users/sign_in', ip: '203.0.113.11', **padded(16_384)),
      step('POST', '/api/v1/auth/login', ip: '203.0.113.12', type: 'text/x-json', body: padded(16_385)[:body]),
      step('POST', '/api/v1/auth/login', ip: '203.0.113.12', **padded(16_384)),
      step('POST', '/users/sign_in', ip: '203.0.113.13',
                                     **form_body("user%5Bemail%5D=big%40example.invalid&pad=#{'x' * 20_000}")),
      step('POST', '/users/sign_in', ip: '203.0.113.14', chunked: true, phoenix: mode == 'cloud' ? 'defer' : nil,
                                     **json_body('user' => { 'email' => 'c@example.invalid' }))
    ]
  end

  def account_link_steps
    [
      *Array.new(6) do |i|
        step('POST', '/auth/account_link/challenge', ip: "203.0.113.#{120 + i}", headers: cookie('link'),
                                                     **form_body('password=x'))
      end,
      step('POST', '/auth/account_link/challenge', ip: '203.0.113.130', headers: cookie('link_string')),
      step('POST', '/auth/account_link/challenge', ip: '203.0.113.131', headers: cookie('link_empty')),
      step('POST', '/auth/account_link/challenge', ip: '203.0.113.132')
    ]
  end

  def unlock_steps
    [
      *Array.new(5) { step('POST', '/s/AbC%2fd/unlock', ip: '203.0.113.150', **form_body('phrase=wrong')) },
      step('POST', '/s/abc%2Fd/unlock.json', ip: '203.0.113.150', **form_body('phrase=wrong')),
      step('POST', '/s/abc/unlock', ip: '127.0.0.1', headers: [['x-forwarded-for', '<garbage>']]),
      step('POST', '/s/abc/unlock', ip: '10.0.0.5', headers: [['forwarded', 'for=198.51.100.4']]),
      *%w[/s/abc/unlock/ //s/abc/unlock /s/abc//unlock].map { |path| step('POST', path, ip: '203.0.113.151') }
    ]
  end
end
