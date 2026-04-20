require 'rails_helper'

RSpec.describe Auth::VerifyOtpChallengeToken do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

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
end
