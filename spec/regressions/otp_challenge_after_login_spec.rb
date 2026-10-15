# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pending OTP challenges after another account signs in', type: :request do
  let(:password) { 'synthetic-password-123' }
  let(:challenged) do
    create(:user, password: password, otp_secret: User.generate_otp_secret, otp_required_for_login: true)
  end
  let(:other) { create(:user, password: password) }

  before do
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
    post user_session_path, params: { user: { email: challenged.email, password: password, remember_me: '1' } }
    expect(session[:otp_user_id]).to eq(challenged.id)
    post user_otp_challenge_path, params: { otp_attempt: 'invalid' }
    expect(session[:otp_failed_attempts]).to eq(1)
  end

  it 'clears all challenge fields after a successful password sign-in' do
    post user_session_path, params: { user: { email: other.email, password: password } }
    expect(response).to redirect_to(root_path)

    %i[otp_user_id otp_challenge_at otp_remember_me otp_failed_attempts].each do |key|
      expect(session[key]).to be_nil
    end
  end

  it 'cannot switch the authenticated account by completing the old challenge' do
    post user_session_path, params: { user: { email: other.email, password: password } }
    post user_otp_challenge_path, params: { otp_attempt: challenged.current_otp }

    expect(response).to redirect_to(new_user_session_path)
    expect(controller.current_user.id).to eq(other.id)
  end

  it 'keeps a pending challenge after unsuccessful password authentication' do
    post user_session_path, params: { user: { email: other.email, password: 'incorrect' } }

    expect(session[:otp_user_id]).to eq(challenged.id)
    expect(session[:otp_failed_attempts]).to eq(1)
  end
end
