# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscription::DecodeJwtToken do
  let(:secret_key) { 'test_secret_key' }

  before do
    stub_const('ENV', ENV.to_h.merge('JWT_SECRET_KEY' => secret_key))
  end

  def encode(payload, key: secret_key)
    JWT.encode(payload, key, 'HS256')
  end

  describe '#call' do
    it 'returns the decoded payload as a symbol-keyed hash' do
      payload = {
        user_id: 42,
        event_id: 'paddle:abc-123',
        event_timestamp_ms: 1_714_000_000_000,
        subscription_source: 'paddle',
        purpose: 'checkout',
        status: 'active',
        active_until: '2026-05-21T00:00:00Z',
        plan: 'pro',
        exp: 30.minutes.from_now.to_i
      }

      decoded = described_class.new(encode(payload)).call

      # Caller relies on symbol-key access (e.g. decoded[:user_id]).
      expect(decoded[:user_id]).to eq(42)
      expect(decoded[:event_id]).to eq('paddle:abc-123')
      expect(decoded[:event_timestamp_ms]).to eq(1_714_000_000_000)
      expect(decoded[:subscription_source]).to eq('paddle')
      expect(decoded[:purpose]).to eq('checkout')
      expect(decoded[:status]).to eq('active')
      expect(decoded[:active_until]).to eq('2026-05-21T00:00:00Z')
      expect(decoded[:plan]).to eq('pro')

      # Defense against accidental string-key drift.
      expect(decoded.keys).to all(be_a(Symbol))
    end

    it 'raises JWT::VerificationError when the token was signed with a different secret' do
      token = encode({ user_id: 1, exp: 30.minutes.from_now.to_i }, key: 'a_different_secret')

      expect { described_class.new(token).call }
        .to raise_error(JWT::VerificationError)
    end

    it 'raises JWT::ExpiredSignature when the token is past its exp claim' do
      token = encode({ user_id: 1, exp: 5.minutes.ago.to_i })

      expect { described_class.new(token).call }
        .to raise_error(JWT::ExpiredSignature)
    end

    it 'raises JWT::DecodeError on malformed input' do
      expect { described_class.new('not.a.jwt').call }
        .to raise_error(JWT::DecodeError)
    end

    it 'raises JWT::DecodeError on a non-JWT string' do
      expect { described_class.new('obviously-not-a-jwt').call }
        .to raise_error(JWT::DecodeError)
    end

    context 'with expected_purpose:' do
      it 'returns the decoded payload when the purpose claim matches' do
        token = encode({ purpose: 'trial_welcome', user_id: 1, jti: 'abc', exp: 30.minutes.from_now.to_i })

        decoded = described_class.new(token, expected_purpose: 'trial_welcome').call

        expect(decoded[:purpose]).to eq('trial_welcome')
      end

      it 'raises InvalidPurpose (a JWT::DecodeError subclass) when the purpose does not match' do
        token = encode({ purpose: 'checkout', user_id: 1, exp: 30.minutes.from_now.to_i })

        expect { described_class.new(token, expected_purpose: 'trial_welcome').call }
          .to raise_error(described_class::InvalidPurpose)

        # The subclass relationship matters: existing controllers `rescue
        # JWT::DecodeError` and we want a purpose mismatch to take the same
        # "link invalid" branch as a tampered token.
        expect(described_class::InvalidPurpose.ancestors).to include(JWT::DecodeError)
      end

      it 'raises InvalidPurpose when the purpose claim is absent' do
        token = encode({ user_id: 1, exp: 30.minutes.from_now.to_i })

        expect { described_class.new(token, expected_purpose: 'trial_welcome').call }
          .to raise_error(described_class::InvalidPurpose)
      end

      it 'returns the decoded payload without checking purpose when expected_purpose is nil' do
        # Manager → Dawarich callback path uses a different claim shape
        # (event_id, event_timestamp_ms) and intentionally has no purpose
        # claim. Skipping the check for nil keeps that contract intact.
        token = encode({ event_id: 'paddle:xyz', user_id: 1, exp: 30.minutes.from_now.to_i })

        expect { described_class.new(token).call }.not_to raise_error
        expect { described_class.new(token, expected_purpose: nil).call }.not_to raise_error
      end
    end
  end
end
