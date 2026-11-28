# frozen_string_literal: true

require 'rails_helper'

# Regression: replacing an already-enabled second factor must require step-up
# (the current password), so a hijacked session cannot swap 2FA.
RSpec.describe '2FA replacement requires step-up', type: :request do
  before { allow(DawarichSettings).to receive(:two_factor_available?).and_return(true) }

  let(:pw) { 'secret123456' }
  let(:user) do
    create(:user, password: pw, password_confirmation: pw,
                  otp_secret: User.generate_otp_secret, otp_required_for_login: true)
  end

  it 'refuses to rotate the secret without the current password' do
    sign_in user
    old_secret = user.otp_secret

    post settings_two_factor_path

    expect(user.reload.otp_secret).to eq(old_secret)
    expect(response).to redirect_to(settings_two_factor_path)
  end

  it 'rotates the secret when the correct current password is supplied' do
    sign_in user
    old_secret = user.otp_secret

    post settings_two_factor_path, params: { current_password: pw }

    expect(user.reload.otp_secret).not_to eq(old_secret)
  end
end
