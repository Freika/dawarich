# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Login after an admin changes a user password', type: :request do
  let!(:admin) { create(:user, :admin, email: 'password-admin@example.test') }
  let!(:user) { create(:user, email: 'password-user@example.test', password: 'original-password-123') }
  let(:new_password) { 'admin-replacement-password-456' }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(Devise).to receive(:mailer_sender).and_return('noreply@example.test')
  end

  shared_examples 'login with the replacement password' do
    it 'accepts the new password through the sign-in endpoint after reporting a successful update' do
      sign_in admin
      patch settings_user_path(user), params: { user: { password: new_password } }

      expect(response).to redirect_to(settings_users_path)
      expect(flash[:notice]).to eq(I18n.t('controllers.settings.users.user_was_successfully_updated'))
      expect(user.reload.valid_password?(new_password)).to be true
      expect(user.valid_password?('original-password-123')).to be false

      delete destroy_user_session_path
      post user_session_path, params: { user: { email: user.email, password: new_password } }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to be_nil
    end
  end

  context 'when the account is not locked' do
    include_examples 'login with the replacement password'
  end

  context 'when the user has already exhausted the allowed password attempts' do
    before do
      User.maximum_attempts.times do
        post user_session_path, params: { user: { email: user.email, password: 'incorrect-password-789' } }
      end

      expect(user.reload.access_locked?).to be true
    end

    include_examples 'login with the replacement password'
  end
end
