# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::VerifyDestroyToken do
  let(:user) { create(:user) }
  let(:secret) { ENV.fetch('JWT_SECRET_KEY') }

  before { Rails.cache.clear }

  describe '#call' do
    it 'returns the user for a freshly issued token' do
      token = Users::IssueDestroyToken.new(user).call
      result = described_class.new(token).call

      expect(result.user).to eq(user)
      expect(result.jti).to be_present
    end

    it 'raises InvalidToken on a blank token' do
      expect { described_class.new(nil).call }.to raise_error(described_class::InvalidToken, /blank/)
    end

    it 'raises InvalidToken on the wrong purpose' do
      payload = { user_id: user.id, purpose: 'something_else', jti: SecureRandom.uuid,
                  iat: Time.now.to_i, exp: 1.hour.from_now.to_i }
      token = JWT.encode(payload, secret, 'HS256')

      expect { described_class.new(token).call }.to raise_error(described_class::InvalidToken, /purpose/)
    end

    it 'raises InvalidToken when the user has been deleted' do
      token = Users::IssueDestroyToken.new(user).call
      user.update!(deleted_at: Time.current)

      expect { described_class.new(token).call }
        .to raise_error(described_class::InvalidToken, /already deleted/)
    end

    it 'raises InvalidToken when the user has been hard-deleted' do
      token = Users::IssueDestroyToken.new(user).call
      User.unscoped.where(id: user.id).delete_all

      expect { described_class.new(token).call }
        .to raise_error(described_class::InvalidToken, /user not found/)
    end

    it 'raises InvalidToken when iat is older than TTL even if exp is wide' do
      payload = { user_id: user.id, purpose: 'account_destroy', jti: SecureRandom.uuid,
                  iat: 2.hours.ago.to_i, exp: 1.day.from_now.to_i }
      token = JWT.encode(payload, secret, 'HS256')

      expect { described_class.new(token).call }
        .to raise_error(described_class::InvalidToken, /too old/)
    end
  end

  describe '.consume!' do
    it 'returns true the first time and false on subsequent calls (atomic)' do
      jti = SecureRandom.uuid

      expect(described_class.consume!(jti)).to be true
      expect(described_class.consume!(jti)).to be false
    end

    it 'returns false for blank jti' do
      expect(described_class.consume!(nil)).to be false
      expect(described_class.consume!('')).to be false
    end
  end
end
