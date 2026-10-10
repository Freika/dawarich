# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::VerifyOtpChallengeToken do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  it 'A11f API auth records JWT claims expiry and cache existence semantics' do
    prior_cache = Rails.cache
    owned_keys = []
    errors = []
    url = "#{ENV.fetch('REDIS_URL')}/0"
    redis = Redis.new(url: url, driver: :ruby)
    Rails.cache = ActiveSupport::Cache::RedisCacheStore.new(
      redis: redis, error_handler: ->(**failure) { errors << failure.fetch(:method) }
    )
    now = Time.utc(2026, 10, 4, 12)
    allow(Auth::InternalTokenSecret).to receive(:call).and_return('a11f-synthetic-jwt-cache')
    travel_to(now) do
      token = Auth::IssueOtpChallengeToken.new(user).call
      claims, header = JWT.decode(token, Auth::InternalTokenSecret.call, true, algorithm: 'HS256')
      expect(header).to eq('alg' => 'HS256')
      expect(claims.keys).to eq(%w[user_id purpose jti iat exp])
      expect(claims.values_at('user_id', 'purpose', 'iat', 'exp')).to eq(
        [user.id, 'otp_challenge', now.to_i, now.to_i + 300]
      )
      expect(claims['jti']).to match(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
      second = Auth::IssueOtpChallengeToken.new(user).call
      expect(JWT.decode(second, Auth::InternalTokenSecret.call, true, algorithm: 'HS256').first['jti'])
        .not_to eq(claims['jti'])
      key = "otp_challenge:consumed:#{claims.fetch('jti')}"
      owned_keys << key
      expect(redis.call('CLIENT', 'INFO')).to include('db=0')
      expect(redis.exists?(key)).to be(false)
      verifier = described_class.new(token)
      expect(verifier.call.id).to eq(user.id)
      expect(redis.exists?(key)).to be(false)
      expect(verifier.mark_consumed!).to be(true)
      expect(Rails.cache.read(key)).to be(true)
      expect(redis.pttl(key)).to be_between(299_000, 300_000)
      raw = redis.get(key)
      ttl = redis.pttl(key)
      expect(verifier.mark_consumed!).to be(false)
      expect(redis.get(key) == raw).to be(true)
      expect(redis.pttl(key)).to be_between(ttl - 1000, ttl)

      [true, false, nil].each do |value|
        Rails.cache.delete(key)
        Rails.cache.write(key, value, expires_in: 300)
        expect(Rails.cache.exist?(key)).to be(true)
        expect { described_class.new(token).call }.to raise_error(described_class::TokenReplayed)
      end
      redis.set(key, 'a11f-corrupt-cache')
      expect(Rails.cache.exist?(key)).to be(false)
      expect(described_class.new(token).call.id).to eq(user.id)
      expired = ActiveSupport::Cache::Entry.new(true, expires_at: now.to_f - 1)
      redis.set(key, Rails.cache.send(:serialize_entry, expired))
      expect(Rails.cache.exist?(key)).to be(false)
      expect(described_class.new(token).call.id).to eq(user.id)
      Rails.cache.delete(key)

      rows = [
        ['age300', { 'iat' => now.to_i - 300, 'exp' => now.to_i + 1 }, :ok],
        ['age301', { 'iat' => now.to_i - 301, 'exp' => now.to_i + 1 }, :invalid],
        ['future', { 'iat' => now.to_i + 60 }, :ok],
        ['expiry-equal', { 'exp' => now.to_i }, :invalid],
        ['expiry-before', { 'exp' => now.to_i - 1 }, :invalid],
        ['no-iat', { 'iat' => nil }, :ok], ['no-exp', { 'exp' => nil }, :ok],
        ['wrong-purpose', { 'purpose' => 'trial_welcome' }, :invalid],
        ['blank-jti', { 'jti' => '  ' }, :invalid],
        ['non-uuid', { 'jti' => 'a11f-non-uuid' }, :ok],
        ['extra', { 'extra' => true }, :ok],
        ['future-nbf', { 'nbf' => now.to_i + 1 }, :invalid],
        ['past-nbf', { 'nbf' => now.to_i - 1 }, :ok],
        ['string-id', { 'user_id' => user.id.to_s }, :ok],
        ['string-iat', { 'iat' => now.to_i.to_s }, :ok],
        ['float-iat', { 'iat' => now.to_i + 0.5 }, :ok],
        ['missing-actor', { 'user_id' => -1 }, :invalid]
      ]
      rows.each do |name, changes, outcome|
        payload = claims.merge(changes).reject { |_field, value| value.nil? }
        candidate = if name == 'string-iat'
                      segments = [header, payload].map do |part|
                        Base64.urlsafe_encode64(JSON.generate(part), padding: false)
                      end
                      input = segments.join('.')
                      digest = OpenSSL::HMAC.digest('SHA256', Auth::InternalTokenSecret.call, input)
                      "#{input}.#{Base64.urlsafe_encode64(digest, padding: false)}"
                    else
                      JWT.encode(payload, Auth::InternalTokenSecret.call, 'HS256')
                    end
        if outcome == :ok
          expect(described_class.new(candidate).call.id).to eq(user.id), name
        else
          expect { described_class.new(candidate).call }.to raise_error(described_class::InvalidToken), name
        end
      end
      %w[HS384 HS512 none].each do |algorithm|
        candidate = JWT.encode(claims, Auth::InternalTokenSecret.call, algorithm)
        expect { described_class.new(candidate).call }.to raise_error(described_class::InvalidToken)
      end
      [nil, '', 'malformed', JWT.encode(claims, 'a11f-wrong-secret', 'HS256')].each do |candidate|
        expect { described_class.new(candidate).call }.to raise_error(described_class::InvalidToken)
      end
      user.update_columns(deleted_at: now)
      expect { described_class.new(token).call }.to raise_error(described_class::InvalidToken, 'user not found')
      user.update_columns(deleted_at: nil)
      allow(redis).to receive(:get).and_raise(Redis::CannotConnectError, 'a11f-cache-read-down')
      expect(described_class.new(token).call.id).to eq(user.id)
      expect(errors).to include(:read_entry)
      allow(redis).to receive(:get).and_call_original
      allow(redis).to receive(:set).and_raise(Redis::CannotConnectError, 'a11f-cache-write-down')
      expect(verifier.mark_consumed!).to be_nil
      expect(errors).to include(:write_entry)
    end
  ensure
    owned_keys&.each { |key| redis.del(key) }
    redis&.close
    Rails.cache = prior_cache
  end

  it 'returns the user for a valid token' do
    token = Auth::IssueOtpChallengeToken.new(user).call
    expect(described_class.new(token).call).to eq(user)
  end

  it 'raises for an expired token' do
    token = Auth::IssueOtpChallengeToken.new(user).call
    travel_to(6.minutes.from_now) do
      expect { described_class.new(token).call }.to raise_error(described_class::InvalidToken)
    end
  end

  it 'raises for a token with the wrong purpose' do
    wrong_token = JWT.encode(
      { user_id: user.id, purpose: 'something_else', exp: 5.minutes.from_now.to_i },
      ENV['JWT_SECRET_KEY'], 'HS256'
    )
    expect { described_class.new(wrong_token).call }.to raise_error(described_class::InvalidToken)
  end

  it 'raises for a token signed with a different secret' do
    wrong_token = JWT.encode(
      { user_id: user.id, purpose: 'otp_challenge', exp: 5.minutes.from_now.to_i },
      'wrong-secret', 'HS256'
    )
    expect { described_class.new(wrong_token).call }.to raise_error(described_class::InvalidToken)
  end

  it 'raises when the user no longer exists' do
    token = Auth::IssueOtpChallengeToken.new(user).call
    user.destroy
    expect { described_class.new(token).call }.to raise_error(described_class::InvalidToken)
  end

  describe 'replay protection' do
    it 'raises TokenReplayed when the token jti has been marked consumed' do
      token = Auth::IssueOtpChallengeToken.new(user).call
      decoded = JWT.decode(token, ENV['JWT_SECRET_KEY'], true, algorithm: 'HS256').first
      Rails.cache.write("otp_challenge:consumed:#{decoded['jti']}", true, expires_in: 5.minutes)

      expect { described_class.new(token).call }.to raise_error(described_class::TokenReplayed)
    end

    it 'TokenReplayed is a kind of InvalidToken so existing rescuers still catch it' do
      expect(described_class::TokenReplayed.new).to be_a(described_class::InvalidToken)
    end
  end

  describe 'issue-time defense-in-depth' do
    it 'rejects a token whose iat is older than the TTL even if exp is still live' do
      old_iat = (Auth::IssueOtpChallengeToken::TTL.ago - 1.minute).to_i
      token = JWT.encode(
        { user_id: user.id, purpose: 'otp_challenge',
          jti: SecureRandom.uuid, iat: old_iat,
          exp: 10.minutes.from_now.to_i },
        ENV['JWT_SECRET_KEY'], 'HS256'
      )
      expect { described_class.new(token).call }.to raise_error(described_class::InvalidToken)
    end
  end
end
