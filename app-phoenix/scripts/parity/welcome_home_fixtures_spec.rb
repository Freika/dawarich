# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'
require 'open3'

RSpec.describe 'Phoenix fixtures: welcome and public home', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/welcome_home') }
  let(:now) { Time.utc(2026, 10, 4, 10) }
  let(:signing_phrase) { 'synthetic-a10b-welcome-signing-phrase' }

  def phoenix(code, extra = {})
    native_env = {
      'PATH' => "#{Dir.home}/.asdf/shims:#{ENV.fetch('PATH')}",
      'ASDF_ERLANG_VERSION' => '27.3.4.1', 'ASDF_ELIXIR_VERSION' => '1.20.4-otp-27',
      'MIX_ENV' => 'test', 'RAILS_ENV' => 'test', 'DATABASE_HOST' => '127.0.0.1',
      'DATABASE_NAME' => ENV.fetch('DATABASE_NAME'), 'PHOENIX_TEST_DATABASE' => ENV.fetch('DATABASE_NAME'),
      'PHOENIX_TEST_REDIS_URL' => ENV.fetch('PHOENIX_TEST_REDIS_URL'),
      'A10B_RAILS_SECRET' => Rails.application.secret_key_base
    }.merge(extra)
    bootstrap = <<~ELIXIR
      for app <- [:ecto_sql, :postgrex, :crypto, :redix, :bcrypt_elixir, :tzdata],
        do: Application.ensure_all_started(app)
      Application.put_env(:dawarich, :rails_secret, System.fetch_env!("A10B_RAILS_SECRET"))
      {:ok, _} = Dawarich.Repo.start_link(database: System.fetch_env!("DATABASE_NAME"),
        pool: DBConnection.ConnectionPool, pool_size: 1, prepare: :unnamed)
      for spec <- Dawarich.Redis.child_specs() ++ Dawarich.Redis.cache_child_specs(),
        do: Supervisor.start_link([spec], strategy: :one_for_one)
    ELIXIR
    output, status = Open3.capture2e(native_env, 'mix', 'run', '--no-start', '-e', bootstrap + code,
                                     chdir: Rails.root.join('app-phoenix').to_s)
    failure = output.lines.grep(/\*\* \(/).first.to_s.split(')').first
    frame = output.lines.find { _1.match?(%r{lib/dawarich[^ ]*:[0-9]+:}) }.to_s.strip
    expect(status.success?).to be(true), "native interoperability failed #{failure}; #{frame}"
    JSON.parse(output.lines.last)
  end

  around do |example|
    saved = ENV['JWT_SECRET_KEY']
    protection = ActionController::Base.allow_forgery_protection
    ENV['JWT_SECRET_KEY'] = signing_phrase
    ActionController::Base.allow_forgery_protection = true
    travel_to(now) do
      if example.metadata[:a10b_non_transactional]
        example.run
      else
        with_legacy_welcome { with_legacy_registration { example.run } }
      end
    end
  ensure
    ENV['JWT_SECRET_KEY'] = saved
    ActionController::Base.allow_forgery_protection = protection
    Rails.cache.delete('dawarich/registration_enabled')
    @owned_keys&.each { |key| Rails.cache.delete(key) }
  end

  before do
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY').and_return(signing_phrase)
    FileUtils.mkdir_p(dir)
    @events = []
    allow(Rails.logger).to receive(:info).and_wrap_original do |original, message = nil, &block|
      if message.is_a?(String) && message.start_with?('{"event":"trial_welcome_consumed"')
        @events << JSON.parse(message)
      end
      original.call(message, &block)
    end
  end

  def welcome_cases
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user = synthetic_user(13_001)
    other = synthetic_user(13_002)
    deleted = synthetic_user(13_003)
    deleted.update_columns(deleted_at: now)
    results = []
    %w[en de es fr pl ca zh].each do |locale|
      capture = welcome_request("valid_#{locale}", user, locale: locale)
      expect(capture['location']).to eq('/map/v2')
      expect(capture['trackable']['sign_in_count_delta']).to eq(1)
      expect(capture['session_rotated']).to be(true)
      expect(capture['events'].map { |event| event['event'] }).to eq(['trial_welcome_consumed'])
      expect(capture['flash']['notice']).to be_present
      expect(capture['flash']['notice']).to include(I18n.l((now + 7.days).to_date, format: :long, locale: locale))
      cookie = cookie_value
      decoded = rails_session(cookie)
      expect(decoded.dig('warden.user.user.key', 0) == [user.id]).to be(true)
      browser = ActionDispatch::Integration::Session.new(Rails.application)
      browser.get('/', headers: { 'Cookie' => "_dawarich_session=#{cookie}" })
      expect(browser.response.status).to eq(302)
      capture['cookie_consumed_by_rails'] = true
      user.update!(password: "a10b-changed-#{locale}-password")
      stale = ActionDispatch::Integration::Session.new(Rails.application)
      stale.get('/', headers: { 'Cookie' => "_dawarich_session=#{cookie}" })
      expect(stale.response.status).to eq(200)
      capture['old_cookie_invalidated'] = true
      results << capture
    end
    user.update_columns(active_until: Time.utc(2026, 10, 11, 23, 30),
                        settings: { 'locale' => 'en', 'timezone' => 'UTC', 'onboarding_completed' => true })
    %w[en de es fr pl ca zh].each do |locale|
      [nil, user].each do |actor|
        name = "midnight_#{actor ? 'actor' : 'guest'}_#{locale}"
        capture = welcome_request(name, user, locale: locale, actor: actor)
        date = Date.new(2026, 10, actor ? 11 : 12)
        expect(capture.dig('flash', 'notice')).to include(I18n.l(date, format: :long, locale: locale))
        results << capture
      end
    end
    user.update_columns(active_until: nil)
    results << welcome_request('active_until_nil', user)
    expect(results.last['flash']['notice']).to include('activated')
    user.update_columns(active_until: now + 7.days)
    [
      ['underscore_exp', { exp: '1_791_109_800' }, true],
      ['underscore_future_nbf', { nbf: '1_791_109_800' }, false],
      ['underscore_past_nbf', { nbf: '1_791_106_200' }, true]
    ].each do |name, overrides, accepted|
      capture = welcome_request(name, user, overrides: overrides)
      expect(capture).to include('signed_in' => accepted, 'claimed' => accepted)
      expect(capture.dig('trackable', 'sign_in_count_delta')).to eq(accepted ? 1 : 0)
      expect(capture.fetch('events').size).to eq(accepted ? 1 : 0)
      results << capture
    end
    malformed = [
      ['missing_token', nil, {}], ['malformed_token', 'not-a-jwt', {}],
      ['wrong_purpose', :signed, { purpose: 'different' }],
      ['missing_purpose', :signed, { purpose: nil }], ['expired', :signed, { exp: now.to_i - 1 }],
      ['missing_exp', :signed, { exp: nil }], ['wrong_algorithm', :hs512, {}],
      ['missing_jti', :signed, { jti: nil }], ['blank_jti', :signed, { jti: ' ' }],
      ['malformed_user_id', :signed, { user_id: 'not-an-id' }], ['missing_user', :signed, { user_id: 13_999 }],
      ['deleted_user', :signed, { user_id: deleted.id }],
      ['malformed_exp', :signed, { exp: 'invalid' }], ['malformed_jti', :signed, { jti: {} }]
    ]
    malformed.each do |name, token, overrides|
      capture = welcome_request(name, user, token: token, overrides: overrides)
      expect(capture['signed_in']).to eq(name == 'malformed_jti')
      expect(capture['claimed']).to eq(name == 'malformed_jti')
      results << capture
    end
    results << welcome_request('different_actor', user, actor: other)
    expect(results.last).to include('location' => '/', 'claimed' => false)
    results << welcome_request('same_actor_first', user, actor: user)
    expect(results.last['trackable']['sign_in_count_delta']).to eq(0)
    replay_jti = 'a10b-welcome-same_actor_first'
    follow_redirect!
    before_count = user.reload.sign_in_count
    @events.clear
    get '/trial/welcome', params: { token: token_for(user, replay_jti) }
    results << welcome_row('same_actor_replay', user, replay_jti, before_count)
    expect(flash[:notice]).to be_blank
    expect(flash[:alert]).to be_blank
    reset!
    @events.clear
    get '/trial/welcome', params: { token: token_for(user, replay_jti) }
    results << welcome_row('guest_replay', user, replay_jti, user.sign_in_count)
    expect(results.last).to include('location' => '/users/sign_in', 'signed_in' => false)
    results << welcome_request('ttl_floor', user, overrides: { exp: now.to_i + 10 })
    expect(results.last['cache']['expires_at']).to eq(now.to_i + 60)
    results << welcome_request('head_success', user, method: :head)
    expect(response.body).to eq('')
    results
  end

  def home_cases
    results = []
    %w[en de es fr pl ca zh].each do |locale|
      [[true, true, 'enabled'], [true, false, 'disabled'], [false, false, 'cloud']].each do |self_hosted, enabled, mode|
        allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
        Rails.cache.write('dawarich/registration_enabled', enabled)
        reset!
        get root_path, params: { locale: locale }, headers: { 'Accept-Language' => locale }
        expect(response.status).to eq(200)
        doc = Nokogiri::HTML5(response.body)
        fragment = doc.at_css('body > div.container > div.w-full > div.flex')
        results << { 'name' => "home_#{locale}_#{mode}", 'path' => '/', 'status' => response.status,
                     'locale' => locale, 'self_hosted' => self_hosted, 'registration' => enabled,
                     'html' => fragment.inner_html, 'navbar' => doc.at_css('.navbar').to_html,
                     'footer' => doc.at_css('footer').to_html,
                     'headers' => response.headers.slice('Cache-Control', 'Content-Type') }
      end
    end
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    reset!
    sign_in synthetic_user(13_001)
    get root_path
    expect(response).to redirect_to('/map/v2')
    results << { 'name' => 'home_signed_in', 'status' => response.status, 'location' => URI(response.location).path }
    results
  end

  def synthetic_user(id)
    create(:user, id: id, email: "a10b-welcome-#{id}@example.invalid", password: 'a10b-synthetic-password',
                  skip_auto_trial: true, status: :trial, active_until: now + 7.days,
                  changelog_consent: :declined, created_at: now, updated_at: now,
                  settings: { 'locale' => 'en', 'onboarding_completed' => true })
  end

  def token_for(user, jti, overrides = {}, algorithm: 'HS256')
    payload = { user_id: user.id, purpose: 'trial_welcome', exp: now.to_i + 1800, jti: jti }.merge(overrides)
    if payload[:exp].is_a?(String) || payload[:nbf].is_a?(String)
      header = Base64.urlsafe_encode64(Oj.dump({ 'alg' => algorithm }, mode: :strict), padding: false)
      body = Base64.urlsafe_encode64(Oj.dump(payload.compact, mode: :strict), padding: false)
      input = "#{header}.#{body}"
      signature = OpenSSL::HMAC.digest('SHA256', signing_phrase, input)
      return "#{input}.#{Base64.urlsafe_encode64(signature, padding: false)}"
    end

    JWT.encode(payload.compact, signing_phrase, algorithm)
  end

  def welcome_request(name, user, locale: 'en', actor: nil, token: :signed, overrides: {}, method: :get)
    reset!
    sign_in(actor) if actor
    get root_path, params: { locale: locale }, headers: { 'Accept-Language' => locale }
    before_count = user.reload.sign_in_count
    previous_session = rails_session(cookie_value)['session_id']
    jti = overrides.key?(:jti) ? overrides[:jti].to_s : "a10b-welcome-#{name}"
    key = "trial_welcome:consumed:#{jti}"
    @owned_keys ||= []
    @owned_keys << key
    Rails.cache.delete(key)
    signed = if token.in?(%i[signed hs512])
               token_for(user, jti, overrides,
                         algorithm: token == :hs512 ? 'HS512' : 'HS256')
             else
               token
             end
    @events.clear
    public_send(method, '/trial/welcome', params: signed.nil? ? {} : { token: signed },
                                        headers: { 'Accept-Language' => locale })
    expect(response.status).to eq(302)
    capture = welcome_row(name, user, jti, before_count)
    capture['locale'] = locale
    capture['session_rotated'] = rails_session(cookie_value)['session_id'] != previous_session
    capture
  end

  def welcome_row(name, user, jti, before_count)
    identity = request.session['warden.user.user.key']
    user.reload
    { 'name' => name, 'status' => response.status, 'location' => URI(response.location).path,
      'headers' => response.headers.slice('Cache-Control', 'Pragma', 'Referrer-Policy', 'Content-Type'),
      'flash' => flash.to_hash.stringify_keys, 'signed_in' => identity&.first == [user.id],
      'claimed' => Rails.cache.read("trial_welcome:consumed:#{jti}") == true,
      'events' => @events.dup,
      'cache' => cache_projection(jti),
      'trackable' => { 'sign_in_count_delta' => user.sign_in_count - before_count,
                       'current_sign_in_at' => user.current_sign_in_at&.utc&.iso8601(6),
                       'last_sign_in_at' => user.last_sign_in_at&.utc&.iso8601(6),
                       'current_sign_in_ip' => user.current_sign_in_ip&.to_s,
                       'last_sign_in_ip' => user.last_sign_in_ip&.to_s } }
  end

  def cache_projection(jti)
    key = "trial_welcome:consumed:#{jti}"
    normalized = Rails.cache.send(:normalize_key, key, {})
    bytes = Rails.cache.redis.with { |redis| redis.get(normalized) }
    return nil unless bytes

    entry = Rails.cache.send(:deserialize_entry, bytes)
    expect(entry.value).to be(true)
    { 'key' => key, 'value' => true, 'expires_at' => entry.expires_at,
      'bytes_hex' => bytes.unpack1('H*') }
  end

  def cookie_value(reply = response)
    line = Array(reply.headers['Set-Cookie']).flat_map { |header| header.split("\n") }
                                             .find { |header| header.start_with?('_dawarich_session=') }
    expect(line.present?).to be(true)
    line.split(';').first.split('=', 2).last
  end

  def rails_session(cookie)
    ActionDispatch::Request.new(Rails.application.env_config.merge('HTTP_COOKIE' => "_dawarich_session=#{cookie}"))
                           .cookie_jar.encrypted['_dawarich_session']
  end

  def save_cases(cases)
    cases.each do |capture|
      name = capture.fetch('name')
      html = capture.fetch('html', '').gsub(/[ \t]+$/, '').rstrip
      FixtureRecording.verify(dir.join("#{name}.html"), "#{html}\n") unless html.empty?
      bytes = Oj.dump(capture.except('html'), mode: :strict, float_precision: 0, indent: 2)
      expect(bytes.include?(signing_phrase)).to be(false)
      FixtureRecording.verify(dir.join("#{name}.json"), "#{bytes.rstrip}\n")
    end
  end

  it 'captures welcome verification replay session and headers' do
    cases = welcome_cases
    expect(cases.map { |capture| capture.fetch('name') }).to eq(
      %w[en de es fr pl ca zh].map { |locale| "valid_#{locale}" } +
       %w[en de es fr pl ca zh].flat_map { |locale| %w[guest actor].map { |actor| "midnight_#{actor}_#{locale}" } } +
       %w[
         active_until_nil underscore_exp underscore_future_nbf underscore_past_nbf
         missing_token malformed_token wrong_purpose missing_purpose
         expired missing_exp wrong_algorithm missing_jti blank_jti malformed_user_id missing_user deleted_user
         malformed_exp malformed_jti different_actor same_actor_first same_actor_replay guest_replay ttl_floor
         head_success
       ]
    )
    expect(cases.find { |capture| capture['name'] == 'guest_replay' })
      .to include('location' => '/users/sign_in', 'signed_in' => false)
    expect(cases.find { |capture| capture['name'] == 'valid_en' })
      .to include('signed_in' => true, 'cookie_consumed_by_rails' => true, 'old_cookie_invalidated' => true)
    cases.each do |capture|
      expect(capture['headers']).to include('Cache-Control' => 'no-store', 'Pragma' => 'no-cache',
                                            'Referrer-Policy' => 'no-referrer')
    end
    save_cases(cases)
  end

  it 'captures anonymous home registration and sign in links in all shipped locales' do
    cases = home_cases
    expect(cases.map { |capture| capture.fetch('name') }).to eq(
      %w[en de es fr pl ca zh].flat_map { |locale|
        %w[enabled disabled cloud].map { |mode|
          "home_#{locale}_#{mode}"
        }
      } +
      ['home_signed_in']
    )
    cases.reject { |capture| capture['name'] == 'home_signed_in' }.each do |capture|
      doc = Nokogiri::HTML5.fragment(capture.fetch('html'))
      expect(doc.css('.card').length).to eq(3)
      expect(doc.css('a[href="/users/sign_in"]').any?).to be(true)
      expect(doc.css('a[href="/users/sign_in"]').text).to eq(I18n.t('home.index.sign_in', locale: capture['locale']))
      expected = !capture['name'].end_with?('disabled')
      expect(doc.css('a[href="/users/sign_up"]').any?).to eq(expected)
      expect(capture.fetch('navbar')).not_to be_empty
      expect(capture.fetch('footer')).not_to be_empty
    end
    save_cases(cases)
  end
  context 'native interoperability', :a10b_non_transactional do
    self.use_transactional_tests = false

    around do |example|
      with_legacy_registration do
        phoenix_registration!
        ActiveRecord::Base.connection.execute('INSERT INTO phoenix.registration_setting (enabled) VALUES (true)')
        example.run
      ensure
        ActiveRecord::Base.connection.execute('DROP TABLE IF EXISTS phoenix.registration_setting')
      end
    end

    before do
      @prior_cache = Rails.cache
      @native_cache = ActiveSupport::Cache::RedisCacheStore.new(url: "#{ENV.fetch('REDIS_URL')}/0", driver: :ruby)
      Rails.cache = @native_cache
      phoenix_state!
      PhoenixSchema.reset!
    end

    after do
      Rails.cache = @prior_cache
      @native_cache.redis.with(&:close)
    end

    it 'Rails consumes native welcome cookie and prevents cross runtime PG replay' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user = synthetic_user(15_921)
      @owned_keys = []
      ['ordinary', 'Grüße', "nul-#{0.chr}-jti"].each do |suffix|
        native_jti = "a13g-native-#{suffix}"
        rails_jti = "a13g-rails-#{suffix}"
        @owned_keys.concat([native_jti, rails_jti].map { "trial_welcome:consumed:#{_1}" })
        @owned_keys.each { |key| Rails.cache.delete(key) }
        count = user.reload.sign_in_count
        native_token = token_for(user, native_jti)
        result = native_welcome(native_token)
        expect(result.fetch('status')).to eq(302)
        expect(result.fetch('location')).to eq('http://www.example.com/map/v2')
        expect(result.fetch('headers')).to include('cache-control' => 'no-store', 'pragma' => 'no-cache',
                                                   'referrer-policy' => 'no-referrer')
        browser = ActionDispatch::Integration::Session.new(Rails.application)
        browser.get('/map/v2', headers: { 'Cookie' => "_dawarich_session=#{result.fetch('cookie')}" })
        identity = browser.request.env.fetch('warden').user(:user)
        expect(identity&.id).to eq(user.id)
        expect(browser.response.status).to eq(200)
        expect(browser.request.flash[:notice]).to eq(I18n.t('controllers.trial.welcome.trial_active_until',
                                                            date: I18n.l((now + 7.days).to_date, format: :long)))
        expect(user.reload.sign_in_count).to eq(count + 1)
        expect(Rails.cache.read("trial_welcome:consumed:#{native_jti}")).to be_nil
        browser.get('/trial/welcome', params: { token: native_token })
        expect(URI(browser.response.location).path).to eq('/map/v2')
        expect(user.reload.sign_in_count).to eq(count + 1)
        alert = I18n.t('controllers.trial.welcome.this_welcome_link_has_already_been_used')
        replay = ActionDispatch::Integration::Session.new(Rails.application)
        replay.get('/trial/welcome', params: { token: native_token })
        expect(URI(replay.response.location).path).to eq('/users/sign_in')
        expect(claim_seconds(pg_welcome_key(native_jti))).to be_between(1798, 1800)
        expect(replay.request.flash[:alert]).to eq(alert)
        rails_token = token_for(user, rails_jti)
        source = ActionDispatch::Integration::Session.new(Rails.application)
        source.get('/trial/welcome', params: { token: rails_token })
        expect(URI(source.response.location).path).to eq('/map/v2')
        expect(claim_seconds(pg_welcome_key(rails_jti))).to be_between(1798, 1800)
        expect(Rails.cache.read("trial_welcome:consumed:#{rails_jti}")).to be_nil
        count = user.reload.sign_in_count
        native_replay = native_welcome(rails_token)
        expect(URI(native_replay.fetch('location')).path).to eq('/users/sign_in')
        expect(user.reload.sign_in_count).to eq(count)
        session = rails_session(native_replay.fetch('cookie'))
        expect(session.dig('flash', 'flashes', 'alert')).to eq(alert)
        same = native_welcome(rails_token, cookie: cookie_value(source.response))
        expect(URI(same.fetch('location')).path).to eq('/map/v2')
        expect(user.reload.sign_in_count).to eq(count)
      end
      large = Array.new(128) { |index| Digest::SHA256.hexdigest("a13g-legacy-large-#{index}") }.join
      signed = token_for(user, large)
      expect(native_welcome(signed, probe: true)).to eq('handoff' => true)
      expect(claim_seconds(pg_welcome_key(large))).to be_nil
      client = ActionDispatch::Integration::Session.new(Rails.application)
      count = user.reload.sign_in_count
      client.get('/trial/welcome', params: { token: signed })
      expect(URI(client.response.location).path).to eq('/map/v2')
      client.get('/trial/welcome', params: { token: signed })
      expect(URI(client.response.location).path).to eq('/map/v2')
      replay = ActionDispatch::Integration::Session.new(Rails.application)
      replay.get('/trial/welcome', params: { token: signed })
      expect(URI(replay.response.location).path).to eq('/users/sign_in')
      expect(user.reload.sign_in_count).to eq(count + 1)
      expect(claim_seconds(pg_welcome_key(large))).to be_between(1798, 1800)
      @owned_keys << "trial_welcome:consumed:#{large}"
    ensure
      User.unscoped.where(id: 15_921).delete_all
      @owned_keys&.each do |key|
        Rails.cache.delete(key)
        digest_key = pg_welcome_key(key.delete_prefix('trial_welcome:consumed:'))
        ActiveRecord::Base.connection.execute("DELETE FROM phoenix.once_claims WHERE key=#{ActiveRecord::Base.connection.quote(digest_key)}")
      end
    end
  end

  def native_welcome(token, cookie: nil, probe: false)
    extra = { 'A10B_TOKEN' => token, 'A10B_NOW' => now.iso8601,
              'A13G_COOKIE' => cookie.to_s, 'A13G_PROBE' => probe.to_s }
    phoenix(<<~ELIXIR, extra)
      {:ok, now, _} = DateTime.from_iso8601(System.fetch_env!("A10B_NOW"))
      context = %{secret: Dawarich.RailsSecret.fetch(), jwt_secret: System.fetch_env!("JWT_SECRET_KEY"),
        env: %{}, oidc: false, clock: fn -> now end}
      query = URI.encode_query(%{"token" => System.fetch_env!("A10B_TOKEN")})
      conn = Plug.Test.conn(:get, "http://www.example.com/trial/welcome?" <> query)
      cookie = System.fetch_env!("A13G_COOKIE")
      conn = if cookie == "", do: conn, else: Plug.Test.put_req_cookie(conn, "_dawarich_session", cookie)
      if System.fetch_env!("A13G_PROBE") == "true" do
        IO.puts(Jason.encode!(%{handoff: not DawarichWeb.WelcomeGate.owned?(conn, %{}, context: context)}))
      else
      conn = DawarichWeb.TrialWelcome.call(conn, context: context)
      IO.puts(Jason.encode!(%{status: conn.status,
        location: List.first(Plug.Conn.get_resp_header(conn, "location")),
        headers: Map.new(conn.resp_headers) |> Map.take(["cache-control", "pragma", "referrer-policy"]),
        cookie: conn.resp_cookies["_dawarich_session"] && conn.resp_cookies["_dawarich_session"].value}))
      end
    ELIXIR
  end

  def pg_welcome_key(jti)
    "trial_welcome:consumed:sha256:#{Digest::SHA256.hexdigest(jti)}"
  end

  def legacy_jti_case(jti)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user = synthetic_user(13_071)
    first = welcome_request('legacy_jti', user, overrides: { jti: jti })
    expect(first).to include('location' => '/map/v2', 'signed_in' => true, 'claimed' => true)
    expect(first.dig('trackable', 'sign_in_count_delta')).to eq(1)
    expect(first.fetch('events').size).to eq(1)
    expect(first.dig('cache', 'expires_at')).to eq(now.to_i + 1800)
    expect(Rails.cache.redis.with { |redis| redis.connection.values_at(:port, :db) })
      .to eq([URI(ENV.fetch('REDIS_URL')).port, 0])
    expect(PhoenixSchema.table?('once_claims')).to be(false)
    follow_redirect!
    count = user.reload.sign_in_count
    @events.clear
    get '/trial/welcome', params: { token: token_for(user, jti) }
    expect(response).to redirect_to('/map/v2')
    expect(user.reload.sign_in_count).to eq(count)
    expect(@events).to be_empty
    expect(flash[:notice]).to be_blank
    reset!
    get '/trial/welcome', params: { token: token_for(user, jti) }
    expect(response).to redirect_to(new_user_session_path)
    expect(request.session['warden.user.user.key']).to be_nil
    expect(user.reload.sign_in_count).to eq(count)
    expect(@events).to be_empty
    expect(response.headers).to include('Cache-Control' => 'no-store', 'Pragma' => 'no-cache',
                                        'Referrer-Policy' => 'no-referrer')
    expect(Rails.cache.read("trial_welcome:consumed:#{jti}")).to be(true)
  end

  it 'legacy welcome oracle uses cache DB0 when once_claims is absent' do
    legacy_jti_case('a13g-legacy-cache')
  end

  it 'legacy welcome NUL jti preserves first consume guest replay and same actor replay' do
    legacy_jti_case("a13g-legacy-#{0.chr}-nul")
  end

  it 'legacy welcome large incompressible jti preserves first consume guest replay and same actor replay' do
    jti = Array.new(128) { |index| Digest::SHA256.hexdigest("a13g-legacy-large-#{index}") }.join
    expect(jti.bytesize).to eq(8192)
    legacy_jti_case(jti)
  end

  it 'characterizes root mobile referral and legacy session effects' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    reset!
    get '/', params: { client: 'ios', aff: 'partner', via: 'ignored' }
    expect(response.status).to eq(200)
    expect(request.session[:dawarich_client]).to eq('ios')
    expect(request.session[:partnero_referral]).to eq('partner')
    expect(request.session['warden.user.user.key']).to be_nil
    head '/'
    expect(response.status).to eq(200)
    expect(response.body).to eq('')
    user = synthetic_user(13_081)
    sign_in user
    get '/', headers: { 'X-Dawarich-Client' => 'android' }
    expect(response).to redirect_to('/map/v2')
    expect(request.session[:dawarich_client]).to eq('android')
    expect(request.session[:partnero_referral]).to eq('partner')
  end
end
