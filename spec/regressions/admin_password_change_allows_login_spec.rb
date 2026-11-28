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

  context 'when the user is one wrong attempt away from the lock' do
    before { user.update_columns(failed_attempts: User.maximum_attempts - 1) }

    it 'clears the attempt count, so one later typo does not lock the account' do
      sign_in admin
      patch settings_user_path(user), params: { user: { password: new_password } }

      expect(user.reload.failed_attempts).to eq(0)
    end
  end

  context 'when the user is locked out of two-factor sign-in' do
    before { user.update_columns(failed_otp_attempts: 5, otp_locked_at: Time.current) }

    it 'clears the two-factor lockout too, as a password reset does' do
      sign_in admin
      patch settings_user_path(user), params: { user: { password: new_password } }

      expect(user.reload).to have_attributes(failed_otp_attempts: 0, otp_locked_at: nil)
    end
  end

  context 'when the new password fails validation' do
    before { user.lock_access!(send_instructions: false) }

    it 'keeps the account locked' do
      sign_in admin
      patch settings_user_path(user), params: { user: { password: 'x' } }

      expect(flash[:alert]).to be_present
      expect(user.reload.access_locked?).to be true
    end
  end

  context 'when an admin edits a locked account without setting a password' do
    before { user.lock_access!(send_instructions: false) }

    it 'keeps the account locked' do
      sign_in admin
      patch settings_user_path(user), params: { user: { password: '', status: 'active' } }

      expect(user.reload.access_locked?).to be true
    end
  end
end
