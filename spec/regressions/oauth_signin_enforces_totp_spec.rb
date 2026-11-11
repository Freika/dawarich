# frozen_string_literal: true

require 'rails_helper'

# Regression: OAuth/OIDC sign-in must challenge a 2FA-enabled account for its
# second factor instead of signing it straight in.
RSpec.describe 'OAuth sign-in enforces 2FA', type: :request do
  before(:all) do
    Rails.application.routes.append do
      devise_scope :user do
        get 'users/auth/google_oauth2/callback', to: 'users/omniauth_callbacks#google_oauth2'
      end
    end
    Rails.application.reload_routes!
  end

  after(:all) { Rails.application.reload_routes! }

  let(:email) { 'otp-oauth@example.com' }
  let!(:user) do
    create(:user, email: email, provider: 'google_oauth2', uid: 'g-1',
                  otp_secret: User.generate_otp_secret, otp_required_for_login: true)
  end

  before do
    Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
    Rails.application.env_config['omniauth.auth'] = OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: 'g-1', info: { email: email, name: 'Dummy' },
      credentials: { token: 'x', expires: false },
      extra: { raw_info: { email: email, email_verified: true, sub: 'g-1' } }
    )
  end

  after { Rails.application.env_config.delete('omniauth.auth') }

  it 'stages the OTP challenge and does not sign the user in' do
    get '/users/auth/google_oauth2/callback'

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('otp_attempt')

    get root_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
