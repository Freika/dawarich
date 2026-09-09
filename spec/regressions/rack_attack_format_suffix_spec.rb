# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rack Attack format suffix protection', type: :request do
  around do |example|
    original_enabled = Rack::Attack.enabled
    original_store = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.enabled = original_enabled
    Rack::Attack.cache.store = original_store
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  cases = {
    'api/points_creation' => POINTS_CREATION_PATHS,
    'api/heavy_recompute' => HEAVY_RECOMPUTE_PATHS,
    'logins/email' => ['/users/sign_in'],
    'logins/ip' => ['/users/sign_in'],
    'logins/api_email' => ['/api/v1/auth/login'],
    'logins/api_ip' => ['/api/v1/auth/login'],
    'signups/api_ip_burst' => ['/api/v1/auth/register'],
    'signups/api_ip_hourly' => ['/api/v1/auth/register'],
    'oauth/token_exchange' => ['/api/v1/auth/apple', '/api/v1/auth/google'],
    'apple_web_callback_per_ip' => ['/users/auth/apple/callback'],
    'users/exist' => ['/api/v1/users/exist'],
    'api/auth/otp_challenge_token' => ['/api/v1/auth/otp_challenge'],
    'api/auth/otp_challenge' => ['/api/v1/auth/otp_challenge'],
    'users/otp_challenge_session' => ['/users/otp_challenge'],
    'users/otp_challenge_ip' => ['/users/otp_challenge'],
    'auth/account_link_challenge_session' => ['/auth/account_link/challenge'],
    'auth/account_link_challenge_ip' => ['/auth/account_link/challenge'],
    'api/users/two_factor_sensitive' => SENSITIVE_2FA_PATHS.to_a,
    'trial/welcome' => ['/trial/welcome'],
    'signups/ip_burst' => ['/users'],
    'signups/ip_hourly' => ['/users'],
    'shared_links/unlock' => ['/s/synthetic-link/unlock']
  }

  def throttle_request(path, method: 'POST')
    Rack::Attack::Request.new(Rack::MockRequest.env_for(
                                path, method: method,
      params: { email: 'test@example.test', user: { email: 'test@example.test' }, challenge_token: 'challenge' },
      'REMOTE_ADDR' => '203.0.113.9',
      'HTTP_AUTHORIZATION' => 'Bearer synthetic-api-key',
      'HTTP_X_WEBHOOK_SECRET' => 'synthetic-secret'
                              ))
  end

  cases.each do |name, paths|
    paths.each do |path|
      it "shares #{name} counters for #{path} across formats" do
        throttle = Rack::Attack.throttles.fetch(name)
        method = name == 'trial/welcome' ? 'GET' : 'POST'
        throttle.limit.times do
          expect(throttle.matched_by?(throttle_request(path, method: method))).to be(false)
        end

        %w[json xml].each do |format|
          expect(throttle.matched_by?(throttle_request("#{path}.#{format}", method: method))).to be(true)
        end
        expect(throttle.matched_by?(throttle_request("#{path}/other", method: method))).to be(false)
      end
    end
  end

  it 'throttles actual API authentication attempts across plain and JSON routes' do
    5.times do
      post '/api/v1/auth/login', params: { email: 'absent@example.test', password: 'wrong' }
      expect(response).to have_http_status(:unauthorized)
    end
    post '/api/v1/auth/login.json', params: { email: 'absent@example.test', password: 'wrong' }
    expect(response).to have_http_status(:too_many_requests)
  end
end
