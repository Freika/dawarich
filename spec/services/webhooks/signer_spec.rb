# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::Signer do
  describe '.sign' do
    it 'produces deterministic HMAC-SHA256 for the same inputs' do
      body = '{"hello":"world"}'
      secret = 'supersecret'
      sig1 = described_class.sign(body: body, secret: secret)
      sig2 = described_class.sign(body: body, secret: secret)
      expect(sig1).to eq(sig2)
    end

    it 'prefixes with sha256=' do
      sig = described_class.sign(body: 'x', secret: 'y')
      expect(sig).to start_with('sha256=')
    end

    it 'produces different signatures for different secrets' do
      body = 'x'
      expect(described_class.sign(body: body, secret: 'a'))
        .not_to eq(described_class.sign(body: body, secret: 'b'))
    end

    it 'matches a known HMAC vector' do
      # HMAC-SHA256(key="key", message="hello") verified with Ruby OpenSSL
      sig = described_class.sign(body: 'hello', secret: 'key')
      expect(sig).to eq('sha256=9307b3b915efb5171ff14d8cb55fbcc798c6c0ef1456d66ded1a6aa723a58b7b')
    end
  end
end
