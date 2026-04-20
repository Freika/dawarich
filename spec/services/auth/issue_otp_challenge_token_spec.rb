require 'rails_helper'

RSpec.describe Auth::IssueOtpChallengeToken do
  let(:user) { create(:user) }

  it 'returns a JWT that decodes to the expected payload' do
    token = described_class.new(user).call
    decoded = JWT.decode(token, ENV['JWT_SECRET_KEY'], true, algorithm: 'HS256').first
    expect(decoded['user_id']).to eq(user.id)
    expect(decoded['purpose']).to eq('otp_challenge')
    expect(decoded['exp']).to be > Time.now.to_i
  end

  it 'expires in 5 minutes' do
    token = described_class.new(user).call
    decoded = JWT.decode(token, ENV['JWT_SECRET_KEY'], true, algorithm: 'HS256').first
    expect(decoded['exp']).to be_within(5).of(5.minutes.from_now.to_i)
  end
end
