# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Phoenix fixture: the Rails session Phoenix writes', type: :request do
  let(:secret) { 'phoenix-a2-cookie-fixture-secret-not-for-production' }
  let(:notice) { "Phoenix wrote this ??? notice &<b>\u2028\u2029" }

  def set_cookie_line(response, name)
    Array(response.headers['Set-Cookie']).flat_map { |line| line.split("\n") }
                                         .find { |line| line.start_with?("#{name}=") }
  end

  def phoenix(code, env = {})
    out, status = Open3.capture2e({ 'MIX_ENV' => 'test', 'PATH' => "#{Dir.home}/.asdf/shims:#{ENV.fetch('PATH')}" }
                                    .merge(env),
                                  'mix', 'run', '--no-start', '-e', code, chdir: Rails.root.join('app-phoenix').to_s)
    expect(status).to be_success, out
    out.lines.last.strip
  end

  def plain(url, method = 'GET') = { 'method' => method, 'url' => url, 'headers' => {} }
  def proxied(headers, url = 'http://dawarich.example/map') = { 'method' => 'GET', 'url' => url, 'headers' => headers }

  def force_ssl_requests
    [plain('http://dawarich.example/map?a=1'), plain('http://dawarich.example/imports', 'POST'),
     plain('http://localhost:3000/map'), plain('http://dawarich.example/map', 'HEAD'),
     plain('https://dawarich.example/map'), proxied({ 'x-forwarded-proto' => 'http' }, 'https://dawarich.example/map'),
     *proxied_scheme_requests]
  end

  def proxied_scheme_requests
    [{ 'x-forwarded-proto' => 'https' }, { 'x-forwarded-proto' => 'http' },
     { 'x-forwarded-proto' => 'http, https' }, { 'x-forwarded-proto' => 'https, http' },
     { 'x-forwarded-proto' => 'https,bogus' }, { 'x-forwarded-proto' => 'http https' },
     { 'x-forwarded-proto' => 'wss' }, { 'x-forwarded-proto' => 'HTTPS' },
     { 'x-forwarded-proto' => 'HTTPS', 'x-forwarded-scheme' => 'https' },
     { 'x-forwarded-ssl' => 'on' }, { 'x-forwarded-ssl' => 'ON' },
     { 'x-forwarded-ssl' => 'on', 'x-forwarded-proto' => 'http' },
     { 'forwarded' => 'proto=https' }, { 'forwarded' => 'proto="https"' }, { 'forwarded' => 'proto="htt\ps"' },
     { 'forwarded' => 'for=192.0.2.1;proto=https, for=198.51.100.2;proto=http' },
     { 'forwarded' => 'proto=http', 'x-forwarded-proto' => 'https' },
     { 'forwarded' => 'proto=bogus', 'x-forwarded-proto' => 'https' },
     { 'forwarded' => 'for=192.0.2.1', 'x-forwarded-proto' => 'https' },
     { 'forwarded' => 'PROTO=https' }, { 'forwarded' => 'proto=HTTPS' }, { 'forwarded' => 'nonce=1;proto=https' },
     { 'x-forwarded-scheme' => 'https' }, { 'x-forwarded-proto' => 'bogus', 'x-forwarded-scheme' => 'https' },
     { 'x-forwarded-proto' => 'http', 'x-forwarded-scheme' => 'https' }].map { |headers| proxied(headers) }
  end

  def sign_in_cookie
    password = 'phoenix-fixture-password'
    user = create(:user, email: 'phoenix-writer@dawarich.test', password: password, password_confirmation: password)
    post user_session_path, params: { user: { email: user.email, password: password } }
    set_cookie_line(response, '_dawarich_session')
  end

  def force_ssl_fixture(line)
    ssl = PhoenixSessionWriterFixture.force_ssl(->(_env) { [200, { 'set-cookie' => line }, []] })
    _, https_headers, = ssl.call(Rack::MockRequest.env_for('https://dawarich.example/'))
    {
      set_cookie: Array(https_headers['set-cookie']).first,
      hsts: https_headers['strict-transport-security'],
      requests: force_ssl_requests.map { |request| PhoenixSessionWriterFixture.answer(ssl, request) },
      forwarded_host: PhoenixSessionWriterFixture.answer(ssl, proxied({ 'x-forwarded-host' => 'evil.example' }))
    }
  end

  def write_fixture(line, value, phoenix_cookie, changes)
    fixture = {
      rails_test_secret: secret,
      rails_settings: PhoenixSessionWriterFixture.settings,
      rails_cookie_json: PhoenixSessionWriterFixture.cookie_json,
      overflow: PhoenixSessionWriterFixture.overflow,
      session_cookie: value,
      set_cookie: line,
      phoenix_session_cookie: phoenix_cookie,
      phoenix_changes: changes,
      force_ssl: force_ssl_fixture(line)
    }
    File.write(Rails.root.join(PhoenixSessionWriterFixture::PATH), "#{JSON.pretty_generate(fixture)}\n")
  end

  def rails_session(value)
    ActionDispatch::Request.new(Rails.application.env_config.merge('HTTP_COOKIE' => "_dawarich_session=#{value}"))
                           .cookie_jar.encrypted['_dawarich_session']
  end

  def inner_json(value)
    salt = Rails.application.config.action_dispatch.authenticated_encrypted_cookie_salt
    ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key(salt, 32),
                                        cipher: 'aes-256-gcm', serializer: ActiveSupport::MessageEncryptor::NullSerializer)
                                   .decrypt_and_verify(Rack::Utils.unescape(value), purpose: 'cookie._dawarich_session')
  end

  def rewrite_in_phoenix(value)
    phoenix(<<~ELIXIR, 'RAILS_COOKIE' => value).split
      secret = "#{secret}"
      token = DawarichWeb.RailsCsrf.new_token()
      flash = %{"discard" => [], "flashes" => %{"notice" => "#{notice}"}}
      changes = %{"locale" => "de", "_csrf_token" => token, "flash" => flash}
      {:ok, cookie} = DawarichWeb.RailsSession.rewrite(System.fetch_env!("RAILS_COOKIE"), changes, secret)
      IO.puts(Enum.join([cookie, DawarichWeb.RailsCsrf.masked_token(%{"_csrf_token" => token}), token], " "))
    ELIXIR
  end

  it 'writes app-phoenix/test/fixtures/rails_session_writer.json and Rails accepts the rewritten session' do
    expect(Rails.application.secret_key_base).to eq(secret)

    line = sign_in_cookie
    value = line.split(';').first.delete_prefix('_dawarich_session=')
    rewritten, masked, token = rewrite_in_phoenix(value)
    changes = { 'locale' => 'de', '_csrf_token' => token,
                'flash' => { 'discard' => [], 'flashes' => { 'notice' => notice } } }
    write_fixture(line, value, rewritten, changes)

    original = rails_session(value)
    expect(original).to include('warden.user.user.key')
    expect(rails_session(rewritten)).to eq(original.merge(changes))
    expect(inner_json(rewritten).bytesize)
      .to eq(PhoenixSessionWriterFixture.cookie_jar.encrypted.send(:serializer).dump(original.merge(changes)).bytesize)
    reset!
    get '/notifications', headers: { 'Cookie' => "_dawarich_session=#{rewritten}" }
    expect(response).to have_http_status(:ok)
    expect(session['locale']).to eq('de')
    expect(flash[:notice]).to eq(notice)
    expect(Base64.urlsafe_decode64(session['_csrf_token']).bytesize)
      .to eq(ActionController::RequestForgeryProtection::AUTHENTICITY_TOKEN_LENGTH)
    expect(session.to_h.except('locale', '_csrf_token', 'flash')).to include(original.except('_csrf_token', 'flash'))

    ActionController::Base.allow_forgery_protection = true
    delete destroy_user_session_path, params: { authenticity_token: masked.reverse },
                                      headers: { 'Cookie' => "_dawarich_session=#{rewritten}" }
    expect(response).to have_http_status(:unprocessable_content)
    delete destroy_user_session_path, params: { authenticity_token: masked },
                                      headers: { 'Cookie' => "_dawarich_session=#{rewritten}" }
    expect(response).to have_http_status(:redirect)
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
