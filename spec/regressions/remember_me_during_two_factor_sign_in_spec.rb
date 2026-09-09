# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Remembering a two-factor sign-in', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { 'test_password_123' }
  let(:user) { create(:user, password: password) }

  before do
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
    user.update!(
      otp_secret: User.generate_otp_secret,
      otp_required_for_login: true
    )
  end

  it 'sets the remember cookie after a successful challenge' do
    post user_session_path,
         params: { user: { email: user.email, password: password, remember_me: '1' } }
    post user_otp_challenge_path, params: { otp_attempt: user.current_otp }

    expect(response.cookies['remember_user_token']).to be_present
  end

  it 'does not remember an unchecked sign-in' do
    post user_session_path,
         params: { user: { email: user.email, password: password, remember_me: '0' } }
    post user_otp_challenge_path, params: { otp_attempt: user.current_otp }

    expect(response.cookies['remember_user_token']).to be_blank
  end

  it 'only remembers after a valid OTP, retaining the choice through a retry' do
    post user_session_path,
         params: { user: { email: user.email, password: password, remember_me: '1' } }
    post user_otp_challenge_path, params: { otp_attempt: 'invalid' }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.cookies['remember_user_token']).to be_blank

    post user_otp_challenge_path, params: { otp_attempt: user.current_otp }

    expect(response.cookies['remember_user_token']).to be_present
  end

  it 'does not carry an expired remember choice into a new unchecked challenge' do
    post user_session_path,
         params: { user: { email: user.email, password: password, remember_me: '1' } }
    travel 6.minutes do
      post user_otp_challenge_path, params: { otp_attempt: user.current_otp }
      expect(response).to redirect_to(new_user_session_path)
      expect(response.cookies['remember_user_token']).to be_blank

      post user_session_path,
           params: { user: { email: user.email, password: password, remember_me: '0' } }
      post user_otp_challenge_path, params: { otp_attempt: user.current_otp }

      expect(response.cookies['remember_user_token']).to be_blank
    end
  end

  it 'restores a remembered sign-in in a new browser session only after completing OTP' do
    post user_session_path,
         params: { user: { email: user.email, password: password, remember_me: '1' } }
    get imports_path
    expect(response).to redirect_to(new_user_session_path)

    post user_otp_challenge_path, params: { otp_attempt: user.current_otp }
    remember_cookie = cookies['remember_user_token']
    expect(remember_cookie).to be_present

    returning_browser = ActionDispatch::Integration::Session.new(Rails.application)
    returning_browser.cookies['remember_user_token'] = remember_cookie
    returning_browser.get imports_path

    expect(returning_browser.response).to have_http_status(:ok)
  end
end
