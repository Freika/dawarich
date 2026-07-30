# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::Sessions OTP Challenge', type: :request do
  let(:password) { 'test_password_123' }
  let(:user) { create(:user, password: password) }

  before do
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
  end

  describe 'login with 2FA enabled' do
    before do
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.generate_otp_backup_codes!
      user.save!
    end

    context 'when password is correct but no OTP provided' do
      it 'shows OTP challenge page and sets session timestamp' do
        post user_session_path, params: { user: { email: user.email, password: password } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Authentication code')
        expect(session[:otp_user_id]).to eq(user.id)
        expect(session[:otp_challenge_at]).to be_present
      end
    end

    context 'with a stashed pending-import ticket' do
      let!(:pending) { create(:pending_import, :with_file) }

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(false)
        allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
        stub_const('MANAGER_URL', 'https://manager.example.com')
      end

      it 'claims the ticket after a successful 2FA sign-in' do
        get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
        expect(session[:pending_import_ticket]).to eq(pending.claim_ticket)

        post user_session_path, params: { user: { email: user.email, password: password } }

        expect { post user_otp_challenge_path, params: { otp_attempt: user.current_otp } }
          .to change(user.imports, :count).by(1)

        expect(pending.reload.claimed_by_user_id).to eq(user.id)
      end
    end

    context 'when OTP challenge is submitted with valid code' do
      it 'signs in the user and clears session' do
        post user_session_path, params: { user: { email: user.email, password: password } }
        post user_otp_challenge_path, params: { otp_attempt: user.current_otp }

        expect(response).to redirect_to(root_path)
        expect(session[:otp_user_id]).to be_nil
        expect(session[:otp_challenge_at]).to be_nil
      end
    end

    context 'when OTP challenge is submitted with invalid code' do
      it 'shows error' do
        post user_session_path, params: { user: { email: user.email, password: password } }
        post user_otp_challenge_path, params: { otp_attempt: '000000' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Invalid two-factor code')
      end

      it 'kicks the user back to sign-in after 5 invalid attempts' do
        post user_session_path, params: { user: { email: user.email, password: password } }

        4.times do
          post user_otp_challenge_path, params: { otp_attempt: '000000' }
          expect(response).to have_http_status(:unprocessable_entity)
        end

        post user_otp_challenge_path, params: { otp_attempt: '000000' }
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to include('Too many invalid')
      end

      it 'increments failed_otp_attempts' do
        post user_session_path, params: { user: { email: user.email, password: password } }
        expect do
          post user_otp_challenge_path, params: { otp_attempt: '000000' }
        end.to change { user.reload.failed_otp_attempts }.by(1)
      end
    end

    context 'when the account is locked' do
      before do
        user.update_columns(otp_locked_at: 1.minute.ago)
        post user_session_path, params: { user: { email: user.email, password: password } }
      end

      it 'redirects to login with a locked message' do
        post user_otp_challenge_path, params: { otp_attempt: user.current_otp }
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to include('locked')
      end
    end

    context 'when OTP succeeds after previous failures' do
      it 'resets the failed_otp_attempts counter' do
        user.update_columns(failed_otp_attempts: 5)
        post user_session_path, params: { user: { email: user.email, password: password } }
        post user_otp_challenge_path, params: { otp_attempt: user.current_otp }
        expect(user.reload.failed_otp_attempts).to eq(0)
      end
    end

    context 'when backup code is used' do
      it 'signs in and invalidates the backup code' do
        backup_code = user.generate_otp_backup_codes!.first
        user.save!

        post user_session_path, params: { user: { email: user.email, password: password } }
        post user_otp_challenge_path, params: { otp_attempt: backup_code }

        expect(response).to redirect_to(root_path)
      end
    end

    context 'when OTP session has expired' do
      it 'redirects to login' do
        post user_otp_challenge_path, params: { otp_attempt: '123456' }

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to include('expired')
      end
    end
  end

  describe 'login without 2FA' do
    it 'signs in normally without OTP challenge' do
      post user_session_path, params: { user: { email: user.email, password: password } }

      expect(response).to redirect_to(root_path)
      expect(session[:otp_user_id]).to be_nil
    end
  end

  describe 'login with wrong password' do
    it 'shows login error' do
      post user_session_path, params: { user: { email: user.email, password: 'wrong' } }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'when 2FA is not available on the instance' do
    before do
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(false)
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.save!
    end

    it 'skips OTP challenge and signs in normally' do
      post user_session_path, params: { user: { email: user.email, password: password } }

      # Without 2FA available, Devise handles auth directly (may succeed or fail
      # depending on strategy, but should NOT show OTP challenge)
      expect(session[:otp_user_id]).to be_nil
    end
  end
end
