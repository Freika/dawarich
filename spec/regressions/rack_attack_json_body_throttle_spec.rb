# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for the JSON-body throttle bypass: rack-attack runs on a
# Rack::Request before ActionDispatch::ParamsParser, so Rack::Request#params
# (and therefore the old safe_params helper) returns {} for application/json
# bodies. Throttles keyed on a JSON body field (the API login email, the OTP
# challenge token) must read and rewind the body themselves via safe_body_params;
# otherwise an attacker rotating IPs could grind passwords against a single
# account without ever tripping the per-email throttle.
RSpec.describe 'Rack Attack JSON body throttle parsing' do
  let(:app) { ->(_env) { [200, {}, ['ok']] } }

  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  after { Rack::Attack.enabled = false }

  def json_env(path, body, method: 'POST', **extra)
    Rack::MockRequest.env_for(
      path,
      method: method,
      input: body,
      'CONTENT_LENGTH' => body.bytesize.to_s,
      'CONTENT_TYPE' => 'application/json',
      **extra
    )
  end

  def json_request(path, body, **extra)
    Rack::Attack::Request.new(json_env(path, body, **extra))
  end

  describe 'safe_body_params' do
    it 'parses the email out of an application/json login body' do
      req = json_request('/api/v1/auth/login', '{"email":"victim@example.com","password":"x"}')

      expect(safe_body_params(req)['email']).to eq('victim@example.com')
    end

    it 'leaves the cheap safe_params helper returning nil for JSON bodies' do
      req = json_request('/api/v1/auth/login', '{"email":"victim@example.com","password":"x"}')

      # safe_params deliberately does NOT parse JSON (Rack::Request#params ignores
      # application/json); this is the original bypass and remains the contract
      # for the cheap path used by request_api_key.
      expect(safe_params(req)['email']).to be_nil
    end

    it 'rewinds the body so downstream middleware / the controller can still read it' do
      req = json_request('/api/v1/auth/login', '{"email":"victim@example.com","password":"x"}')

      safe_body_params(req)

      expect(req.body.read).to eq('{"email":"victim@example.com","password":"x"}')
    end

    it 'reads and parses the body only once across multiple helper calls' do
      raw = '{"email":"victim@example.com","password":"x"}'
      req = json_request('/api/v1/auth/login', raw)

      # Count actual stream reads; rack-attack must not chew through the body
      # repeatedly when several throttles read params in one request.
      read_count = 0
      original_read = req.body.method(:read)
      allow(req.body).to receive(:read) do |*args|
        read_count += 1
        original_read.call(*args)
      end

      3.times { safe_body_params(req) }

      expect(read_count).to eq(1)
    end

    it 'merges the JSON body over the query string (body wins, mirroring Rack::Request#params)' do
      req = json_request(
        '/api/v1/auth/login?email=query@example.com',
        '{"email":"body@example.com","password":"x"}'
      )

      merged = safe_body_params(req)
      expect(merged['email']).to eq('body@example.com')
    end

    it 'falls back to the query string when the JSON body is malformed' do
      req = json_request(
        '/api/v1/auth/login?email=query@example.com',
        '--- not json'
      )

      expect(safe_body_params(req)['email']).to eq('query@example.com')
    end

    it 'falls back to the query string when the JSON body is a non-object (array)' do
      req = json_request('/api/v1/auth/login', '["email","victim@example.com"]')

      expect(safe_body_params(req)).to eq({})
    end

    it 'falls back to the query string when the JSON body is empty' do
      req = json_request('/api/v1/auth/login?email=query@example.com', '')

      expect(safe_body_params(req)['email']).to eq('query@example.com')
    end

    it 'delegates to safe_params for form-encoded bodies (no JSON parsing)' do
      env = Rack::MockRequest.env_for(
        '/api/v1/auth/login',
        method: 'POST',
        params: { 'email' => 'form@example.com', 'password' => 'x' }
      )
      req = Rack::Attack::Request.new(env)

      expect(safe_body_params(req)['email']).to eq('form@example.com')
      # No JSON memoisation for form-encoded bodies.
      expect(req.env.key?('rack.attack.parsed_body')).to be(false)
    end

    it 'returns the email unchanged so the throttle normalises casing/whitespace' do
      req = json_request('/api/v1/auth/login', '{"email":"  Victim@Example.com  ","password":"x"}')

      # Normalisation (downcase + strip) is the throttle's job; the helper
      # returns the raw submitted value.
      expect(safe_body_params(req)['email']).to eq('  Victim@Example.com  ')
    end

    UNPARSEABLE_BODY_ERRORS.each do |error_class|
      it "falls back to the query string when params raises #{error_class}" do
        env = Rack::MockRequest.env_for('/api/v1/auth/login?email=query@example.com', method: 'POST')
        request = Rack::Attack::Request.new(env)
        allow(request).to receive(:media_type).and_return('application/json')
        allow(request).to receive_message_chain(:body, :read).and_raise(error_class)

        expect(safe_body_params(request)['email']).to eq('query@example.com')
      end
    end
  end

  describe 'logins/api_email throttle (JSON body)' do
    let(:throttle) { Rack::Attack.throttles.fetch('logins/api_email') }

    it 'counts JSON login attempts against the per-email bucket' do
      req = lambda do |email|
        json_request(
          '/api/v1/auth/login',
          { email: email, password: 'wrong' }.to_json,
          'REMOTE_ADDR' => '203.0.113.7'
        )
      end

      throttle.limit.times do
        expect(throttle.matched_by?(req.call('victim@example.com'))).to be(false)
      end

      expect(throttle.matched_by?(req.call('victim@example.com'))).to be(true)
    end

    it 'normalises casing/whitespace so case variants share one bucket' do
      req = lambda do |email|
        json_request(
          '/api/v1/auth/login',
          { email: email, password: 'wrong' }.to_json,
          'REMOTE_ADDR' => '203.0.113.7'
        )
      end

      throttle.limit.times { throttle.matched_by?(req.call('victim@example.com')) }
      expect(throttle.matched_by?(req.call('  VICTIM@EXAMPLE.COM  '))).to be(true)
    end

    it 'extracts the per-email discriminator from a JSON body (the original bypass left it nil)' do
      req = json_request(
        '/api/v1/auth/login',
        { email: 'victim@example.com', password: 'wrong' }.to_json
      )
      throttle.matched_by?(req)

      data = req.env['rack.attack.throttle_data'].fetch('logins/api_email')
      expect(data[:discriminator]).to eq('victim@example.com')
      expect(data[:count]).to eq(1)
    end
  end

  describe 'api/auth/otp_challenge_token throttle (JSON body)' do
    let(:throttle) { Rack::Attack.throttles.fetch('api/auth/otp_challenge_token') }

    it 'counts JSON OTP attempts against the per-token bucket' do
      req = lambda do |token|
        json_request(
          '/api/v1/auth/otp_challenge',
          { challenge_token: token, otp_code: '000000' }.to_json,
          'REMOTE_ADDR' => '203.0.113.8'
        )
      end

      throttle.limit.times do
        expect(throttle.matched_by?(req.call('synthetic-challenge-token'))).to be(false)
      end

      expect(throttle.matched_by?(req.call('synthetic-challenge-token'))).to be(true)
    end
  end

  describe 'request_api_key (JSON body is not read)' do
    it 'does not parse the JSON body to look up api_key (keeps ingestion hot path cheap)' do
      req = json_request(
        '/api/v1/points?api_key=query-key',
        '{"data":[{"lat":1,"lng":2},{"lat":3,"lng":4}]}'
      )

      # api_key is contractually a query string or Bearer header (swagger
      # `in: :query`); the JSON body is not read for the api/token throttle.
      expect(request_api_key(req)).to eq('query-key')
      expect(req.env.key?('rack.attack.parsed_body')).to be(false)
    end
  end
end
