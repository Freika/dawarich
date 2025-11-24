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
        around do |example|
          original_value = ENV['ALLOW_EMAIL_PASSWORD_REGISTRATION']
          ENV['ALLOW_EMAIL_PASSWORD_REGISTRATION'] = 'true'
          example.run
          ENV['ALLOW_EMAIL_PASSWORD_REGISTRATION'] = original_value
        end

        it 'returns true' do
          expect(helper.email_password_registration_enabled?).to be true
        end
      end

      context 'when ALLOW_EMAIL_PASSWORD_REGISTRATION is false' do
        around do |example|
          original_value = ENV['ALLOW_EMAIL_PASSWORD_REGISTRATION']
          ENV['ALLOW_EMAIL_PASSWORD_REGISTRATION'] = 'false'
          example.run
          ENV['ALLOW_EMAIL_PASSWORD_REGISTRATION'] = original_value
        end

        it 'returns false' do
          expect(helper.email_password_registration_enabled?).to be false
        end
      end

      context 'when ALLOW_EMAIL_PASSWORD_REGISTRATION is not set' do
        around do |example|
          original_value = ENV['ALLOW_EMAIL_PASSWORD_REGISTRATION']
          ENV.delete('ALLOW_EMAIL_PASSWORD_REGISTRATION')
          example.run
          ENV['ALLOW_EMAIL_PASSWORD_REGISTRATION'] = original_value
        end

        it 'returns false (default)' do
          expect(helper.email_password_registration_enabled?).to be false
        end
      end
    end
  end
end
