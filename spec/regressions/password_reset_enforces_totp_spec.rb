# frozen_string_literal: true

require 'rails_helper'

# Regression: password reset must not auto-sign-in a 2FA-enabled account; it must
# still go through the OTP challenge.
RSpec.describe 'Password reset enforces 2FA', type: :request do
  before { allow(DawarichSettings).to receive(:two_factor_available?).and_return(true) }

  let(:new_password) { SecureRandom.hex(12) }
  let(:user) do
    create(:user, password: SecureRandom.hex(12),
                  otp_secret: User.generate_otp_secret, otp_required_for_login: true)
  end

  it 'resets the password but does not establish a session' do
    raw, enc = Devise.token_generator.generate(User, :reset_password_token)
    user.update!(reset_password_token: enc, reset_password_sent_at: Time.current)

    put '/users/password', params: { user: {
      reset_password_token: raw, password: new_password, password_confirmation: new_password
    } }

    expect(user.reload.valid_password?(new_password)).to be(true)

    get root_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
