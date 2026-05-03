# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trial::Resume', type: :request do
  before do
    stub_const('MANAGER_URL', 'https://manager.example.test')
  end

  describe 'GET /trial/resume' do
    context 'when user is pending_payment' do
      let(:user) do
        u = create(:user, skip_auto_trial: true)
        u.update_column(:status, User.statuses[:pending_payment])
        u
      end

      before { sign_in(user) }

      it 'renders the page for pending_payment users' do
        get trial_resume_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Finish setting up your account')
      end

      it 'sends Cache-Control: no-store so proxies do not cache the embedded JWT' do
        get trial_resume_path

        expect(response.headers['Cache-Control']).to include('no-store')
      end

      it 'includes the Manager checkout link with a fresh JWT' do
        get trial_resume_path

        expect(response.body).to match(%r{https://manager\.example\.test/checkout\?token=})

        token_match = response.body.match(%r{https://manager\.example\.test/checkout\?token=([^"'&\s]+)})
        expect(token_match).not_to be_nil

        token = token_match[1]
        payload = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, { algorithm: 'HS256' }).first

        expect(payload['variant']).to eq('reverse_trial')
        expect(payload['user_id']).to eq(user.id)
      end
    end

    context 'when user is not pending_payment' do
      let(:user) { create(:user) }

      before { sign_in(user) }

      it 'redirects to root_path' do
        get trial_resume_path

        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'POST /users/sign_in for pending_payment users' do
    it 'redirects pending_payment users to /trial/resume after login' do
      user = create(:user, password: 'secret123456', skip_auto_trial: true)
      user.update_column(:status, User.statuses[:pending_payment])

      post user_session_path, params: { user: { email: user.email, password: 'secret123456' } }

      expect(response).to redirect_to(trial_resume_path)
    end
  end
end
