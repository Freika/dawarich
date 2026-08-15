# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Email/password login visibility when OIDC is enabled', type: :helper do
  describe '#email_password_login_enabled?' do
    before { allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true) }

    context 'with the registration flag off' do
      before { allow(DawarichSettings).to receive(:registration_enabled?).and_return(false) }

      it 'still allows email/password login by default' do
        stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', true)

        expect(helper.email_password_login_enabled?).to be true
      end

      it 'is independent of the registration flag' do
        stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', true)

        expect(helper.email_password_login_enabled?).to be true
        expect(DawarichSettings.registration_enabled?).to be false
      end
    end

    context 'when an operator opts into OIDC-only login' do
      before { allow(DawarichSettings).to receive(:registration_enabled?).and_return(true) }

      it 'hides the email/password form when ALLOW_EMAIL_PASSWORD_LOGIN is false' do
        stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', false)

        expect(helper.email_password_login_enabled?).to be false
      end
    end
  end
end
