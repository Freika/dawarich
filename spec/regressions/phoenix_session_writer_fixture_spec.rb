# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix port: the Rails session and force_ssl settings pinned in the Phoenix writer fixture',
               type: :request do
  let(:fixture) { PhoenixSessionWriterFixture.read }

  def fixture_jar(value)
    secret = fixture['rails_test_secret']
    env = Rails.application.env_config.merge(
      'action_dispatch.secret_key_base' => secret,
      'action_dispatch.key_generator' => Rails.application.key_generator(secret),
      'HTTP_COOKIE' => "_dawarich_session=#{value}"
    )
    ActionDispatch::Request.new(env).cookie_jar
  end

  it 'matches the live SSL, session and cookie JSON settings Phoenix mirrors' do
    expect(PhoenixSessionWriterFixture.settings).to eq(fixture['rails_settings'])
    expect(PhoenixSessionWriterFixture.cookie_json).to eq(fixture['rails_cookie_json'])
    expect(PhoenixSessionWriterFixture.overflow).to eq(fixture['overflow'])
  end

  it 'answers every recorded force_ssl request as the fixture says' do
    ssl = PhoenixSessionWriterFixture.force_ssl
    requests = fixture['force_ssl']['requests'] + [fixture['force_ssl']['forwarded_host']]

    expect(requests.map { |request| PhoenixSessionWriterFixture.answer(ssl, request) }).to eq(requests)
  end

  it 'issues the session cookie with the attributes Phoenix copies, secure under force_ssl' do
    password = 'phoenix-fixture-password'
    user = create(:user, password: password, password_confirmation: password)
    post user_session_path, params: { user: { email: user.email, password: password } }
    line = Array(response.headers['Set-Cookie']).flat_map { |header| header.split("\n") }
                                                .find { |header| header.start_with?('_dawarich_session=') }
    ssl = PhoenixSessionWriterFixture.force_ssl(->(_env) { [200, { 'set-cookie' => line }, []] })
    _, https_headers, = ssl.call(Rack::MockRequest.env_for('https://dawarich.example/'))

    expect(PhoenixSessionWriterFixture.cookie_attributes(line))
      .to eq(PhoenixSessionWriterFixture.cookie_attributes(fixture['set_cookie']))
    expect(PhoenixSessionWriterFixture.cookie_attributes(Array(https_headers['set-cookie']).first))
      .to eq(PhoenixSessionWriterFixture.cookie_attributes(fixture['force_ssl']['set_cookie']))
    expect(https_headers['strict-transport-security']).to eq(fixture['force_ssl']['hsts'])
  end

  it 'reads the session Phoenix wrote with the live cookie settings, losing no Rails key' do
    original = fixture_jar(fixture['session_cookie']).encrypted['_dawarich_session']

    expect(original).to include('warden.user.user.key')
    expect(fixture_jar(fixture['phoenix_session_cookie']).encrypted['_dawarich_session'])
      .to eq(original.merge(fixture['phoenix_changes']))
  end
end
