# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoExports::CallbackToken do
  include ActiveSupport::Testing::TimeHelpers

  let(:video_export_id) { 42 }
  let(:nonce) { SecureRandom.urlsafe_base64(32) }

  describe '.generate' do
    it 'returns a base64-encoded string' do
      token = described_class.generate(video_export_id, nonce)

      expect(token).to be_a(String)
      expect { Base64.urlsafe_decode64(token) }.not_to raise_error
    end

    it 'includes the video_export_id and nonce in the token payload' do
      token = described_class.generate(video_export_id, nonce)
      decoded = Base64.urlsafe_decode64(token)
      parts = decoded.split(':')

      expect(parts[0].to_i).to eq(video_export_id)
      expect(parts[1]).to eq(nonce)
    end
  end

  describe '.verify' do
    it 'returns true for a valid token' do
      token = described_class.generate(video_export_id, nonce)

      expect(described_class.verify(token, video_export_id, nonce)).to be true
    end

    it 'returns false for an expired token' do
      token = described_class.generate(video_export_id, nonce)

      travel_to 2.hours.from_now do
        expect(described_class.verify(token, video_export_id, nonce)).to be false
      end
    end

    it 'returns false for a tampered token' do
      token = described_class.generate(video_export_id, nonce)
      decoded = Base64.urlsafe_decode64(token)
      parts = decoded.split(':')
      parts[3] = 'tampered_digest'
      tampered = Base64.urlsafe_encode64(parts.join(':'))

      expect(described_class.verify(tampered, video_export_id, nonce)).to be false
    end

    it 'returns false for nil token' do
      expect(described_class.verify(nil, video_export_id, nonce)).to be false
    end

    it 'returns false for wrong video_export_id' do
      token = described_class.generate(video_export_id, nonce)

      expect(described_class.verify(token, 999, nonce)).to be false
    end

    it 'returns false for wrong nonce' do
      token = described_class.generate(video_export_id, nonce)

      expect(described_class.verify(token, video_export_id, 'wrong_nonce')).to be false
    end

    it 'returns false for malformed base64' do
      expect(described_class.verify('not-valid-base64!!!', video_export_id, nonce)).to be false
    end

    it 'returns false for empty string' do
      expect(described_class.verify('', video_export_id, nonce)).to be false
    end
  end
end
