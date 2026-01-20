# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe '#oauth_provider_name' do
    context 'when provider is openid_connect' do
      it 'returns the custom OIDC provider name' do
        stub_const('OIDC_PROVIDER_NAME', 'Authentik')

        expect(helper.oauth_provider_name(:openid_connect)).to eq('Authentik')
      end

      it 'returns default name when OIDC_PROVIDER_NAME is not set' do
        stub_const('OIDC_PROVIDER_NAME', 'Openid Connect')

        expect(helper.oauth_provider_name(:openid_connect)).to eq('Openid Connect')
      end
    end

    context 'when provider is not openid_connect' do
      it 'returns camelized provider name for github' do
        expect(helper.oauth_provider_name(:github)).to eq('GitHub')
      end

      it 'returns camelized provider name for google_oauth2' do
        expect(helper.oauth_provider_name(:google_oauth2)).to eq('GoogleOauth2')
      end
    end
  end

  describe '#email_password_registration_enabled?' do
    context 'in cloud mode' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'returns true' do
        expect(helper.email_password_registration_enabled?).to be true
      end
    end

    context 'in self-hosted mode' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end

      context 'when ALLOW_EMAIL_PASSWORD_REGISTRATION is true' do
        before do
          stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)
        end

        it 'returns true' do
          expect(helper.email_password_registration_enabled?).to be true
        end
      end

      context 'when ALLOW_EMAIL_PASSWORD_REGISTRATION is false' do
        before do
          stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', false)
        end

        it 'returns false' do
          expect(helper.email_password_registration_enabled?).to be false
        end
      end

      context 'when ALLOW_EMAIL_PASSWORD_REGISTRATION is not set (default)' do
        before do
          stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', false)
        end

        it 'returns false (default)' do
          expect(helper.email_password_registration_enabled?).to be false
        end
      end
    end
  end

  describe '#email_password_login_enabled?' do
    context 'when OIDC is not enabled' do
      before do
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
      end

      it 'returns true regardless of ALLOW_EMAIL_PASSWORD_REGISTRATION' do
        stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', false)

        expect(helper.email_password_login_enabled?).to be true
      end
    end

    context 'in cloud mode with OAuth providers (GitHub/Google)' do
      before do
        # Cloud mode: self_hosted? is false, so oidc_enabled? returns false
        # even if there are OAuth providers configured
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
      end

      it 'always returns true (OAuth is supplementary to email/password)' do
        stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', false)

        expect(helper.email_password_login_enabled?).to be true
      end
    end

    context 'when OIDC is enabled' do
      before do
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)
      end

      context 'when ALLOW_EMAIL_PASSWORD_REGISTRATION is true' do
        before do
          stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)
        end

        it 'returns true' do
          expect(helper.email_password_login_enabled?).to be true
        end
      end

      context 'when ALLOW_EMAIL_PASSWORD_REGISTRATION is false' do
        before do
          stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', false)
        end

        it 'returns false (OIDC-only mode)' do
          expect(helper.email_password_login_enabled?).to be false
        end
      end
    end
  end

  describe '#preferred_map_path' do
    context 'when user is not signed in' do
      before do
        allow(helper).to receive(:user_signed_in?).and_return(false)
      end

      it 'returns map_v2_path by default' do
        expect(helper.preferred_map_path).to eq(helper.map_v2_path)
      end
    end

    context 'when user is signed in' do
      let(:user) { create(:user) }

      before do
        allow(helper).to receive(:user_signed_in?).and_return(true)
        allow(helper).to receive(:current_user).and_return(user)
      end

      context 'when user has no preferred_version set' do
        before do
          user.settings['maps'] = { 'distance_unit' => 'km' }
          user.save
        end

        it 'returns map_v2_path as the default' do
          expect(helper.preferred_map_path).to eq(helper.map_v2_path)
        end
      end

      context 'when user has preferred_version set to v1' do
        before do
          user.settings['maps'] = { 'preferred_version' => 'v1', 'distance_unit' => 'km' }
          user.save
        end

        it 'returns map_v1_path' do
          expect(helper.preferred_map_path).to eq(helper.map_v1_path)
        end
      end

      context 'when user has preferred_version set to v2' do
        before do
          user.settings['maps'] = { 'preferred_version' => 'v2', 'distance_unit' => 'km' }
          user.save
        end

        it 'returns map_v2_path' do
          expect(helper.preferred_map_path).to eq(helper.map_v2_path)
        end
      end

      context 'when user has no maps settings at all' do
        before do
          user.settings.delete('maps')
          user.save
        end

        it 'returns map_v2_path as the default' do
          expect(helper.preferred_map_path).to eq(helper.map_v2_path)
        end
      end
    end
  end
end
