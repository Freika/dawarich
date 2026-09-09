# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rack Attack malformed multipart handling' do
  let(:app) { ->(_env) { [200, {}, ['ok']] } }

  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  after do
    Rack::Attack.enabled = false
  end

  def malformed_multipart_env(path, headers = {})
    Rack::MockRequest.env_for(
      path,
      method: 'POST',
      input: 'x',
      'CONTENT_LENGTH' => '1',
      'CONTENT_TYPE' => 'multipart/form-data; boundary=synthetic-boundary',
      **headers
    )
  end

  it 'uses a query-string API key when multipart parsing fails' do
    env = malformed_multipart_env('/api/v1/imports?api_key=synthetic-key')

    expect(request_api_key(Rack::Request.new(env))).to eq('synthetic-key')
    expect { Rack::Attack.new(app).call(env) }.not_to raise_error
  end

  it 'uses a bearer token when multipart parsing fails' do
    env = malformed_multipart_env(
      '/api/v1/imports',
      'HTTP_AUTHORIZATION' => 'Bearer synthetic-key'
    )

    expect(request_api_key(Rack::Request.new(env))).to eq('synthetic-key')
    expect { Rack::Attack.new(app).call(env) }.not_to raise_error
  end

  it 'preserves body-only API keys for valid requests' do
    env = Rack::MockRequest.env_for(
      '/api/v1/points',
      method: 'POST',
      input: 'api_key=body-key',
      'CONTENT_TYPE' => 'application/x-www-form-urlencoded'
    )

    expect(request_api_key(Rack::Request.new(env))).to eq('body-key')
  end

  it 'preserves parameter precedence over bearer authentication' do
    env = Rack::MockRequest.env_for(
      '/api/v1/points?api_key=query-key',
      'HTTP_AUTHORIZATION' => 'Bearer bearer-key'
    )

    expect(request_api_key(Rack::Request.new(env))).to eq('query-key')
  end

  it 'keeps query-string precedence over bearer when the body cannot be parsed' do
    env = malformed_multipart_env(
      '/api/v1/imports?api_key=query-key',
      'HTTP_AUTHORIZATION' => 'Bearer bearer-key'
    )

    expect(request_api_key(Rack::Request.new(env))).to eq('query-key')
  end

  # Rack raises a different class per malformation; the throttle must survive
  # every one of them rather than only the empty-body case.
  UNPARSEABLE_BODY_ERRORS.each do |error_class|
    it "falls back to the query string when params raises #{error_class}" do
      env = Rack::MockRequest.env_for('/api/v1/imports?api_key=synthetic-key', method: 'POST')
      request = Rack::Request.new(env)
      allow(request).to receive(:params).and_raise(error_class)

      expect(request_api_key(request)).to eq('synthetic-key')
    end
  end

  # These throttles read params for their own key. `logins/email` has no
  # self-hosted guard, so an unparseable body there reached every instance.
  {
    'sign-in' => '/users/sign_in',
    'api login' => '/api/v1/auth/login',
    'otp challenge' => '/api/v1/auth/otp_challenge'
  }.each do |label, path|
    it "survives a malformed multipart body posted to #{label}" do
      env = malformed_multipart_env(path)

      expect { Rack::Attack.new(app).call(env) }.not_to raise_error
      expect(Rack::Attack.new(app).call(env).first).to eq(200)
    end
  end

  # Dropping the email key on an unparseable body is deliberate fail-open, and
  # it is safe only because the IP-keyed throttle on the same path still counts.
  it 'still counts a malformed sign-in against the IP throttle' do
    stack = Rack::Attack.new(app)
    statuses = Array.new(21) do
      stack.call(malformed_multipart_env('/users/sign_in', 'REMOTE_ADDR' => '203.0.113.9')).first
    end

    expect(statuses.first).to eq(200)
    expect(statuses.last).to eq(429)
  end

  it 'still throttles sign-in by email when the body parses normally' do
    env = Rack::MockRequest.env_for(
      '/users/sign_in',
      method: 'POST',
      params: { 'user' => { 'email' => 'Person@Example.test ' } }
    )

    expect(safe_params(Rack::Request.new(env)).dig('user', 'email')).to eq('Person@Example.test ')
    expect { Rack::Attack.new(app).call(env) }.not_to raise_error
  end

  it 'falls back to an empty hash when body and query are both unparseable' do
    env = Rack::MockRequest.env_for('/users/sign_in', method: 'POST')
    request = Rack::Request.new(env)
    allow(request).to receive(:params).and_raise(Rack::Multipart::EmptyContentError)
    allow(request).to receive(:GET).and_raise(Rack::QueryParser::InvalidParameterError)

    expect(safe_params(request)).to eq({})
  end

  it 'returns nil when neither the body nor the query string can be parsed' do
    env = Rack::MockRequest.env_for('/api/v1/imports', method: 'POST')
    request = Rack::Request.new(env)
    allow(request).to receive(:params).and_raise(Rack::Multipart::EmptyContentError)
    allow(request).to receive(:GET).and_raise(Rack::QueryParser::InvalidParameterError)

    expect(request_api_key(request)).to be_nil
  end
end
