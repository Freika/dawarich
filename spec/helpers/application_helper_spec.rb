# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe '#pro_badge_tag' do
    context 'when user is not lite' do
      before do
        allow(helper).to receive(:current_user).and_return(double(lite?: false))
      end

      it 'returns nil' do
        expect(helper.pro_badge_tag).to be_nil
      end
    end

    context 'when user is lite' do
      let(:fake_user) { double(lite?: true, generate_subscription_token: 'test_token') }

      before do
        allow(helper).to receive(:current_user).and_return(fake_user)
        # Stub icon helper used inside pro_badge_tag
        allow(helper).to receive(:icon).and_return('🔒'.html_safe)
        # Provide a controller context for rails_pulse's link_to override
        allow(helper).to receive(:controller).and_return(
          double(class: double(name: 'ApplicationController'))
        )
      end

      it 'renders a DaisyUI tooltip with data-tip attribute' do
        result = helper.pro_badge_tag
        expect(result).to include('tooltip')
        expect(result).to include('tooltip-bottom')
        expect(result).to include('data-tip=')
      end

      it 'includes preview text when preview is true' do
        result = helper.pro_badge_tag(preview: true)
        expect(result).to include('Available on Pro')
        expect(result).to include('click to preview')
      end

      it 'excludes preview text when preview is false' do
        result = helper.pro_badge_tag(preview: false)
        expect(result).to include('Available on Pro')
        expect(result).not_to include('click to preview')
      end

      it 'does not use native title attribute' do
        result = helper.pro_badge_tag
        expect(result).not_to include(' title=')
      end

      it 'renders as a link to the subscription manager' do
        result = helper.pro_badge_tag
        expect(result).to include('<a ')
        expect(result).to include("#{MANAGER_URL}/auth/dawarich")
        expect(result).to include('token=test_token')
        expect(result).to include('target="_blank"')
        expect(result).to include('tabindex="0"')
      end
    end
  end

  describe '#oauth_button_config' do
    context 'when provider is google_oauth2' do
      subject(:config) { helper.oauth_button_config(:google_oauth2) }

      it 'returns Google label' do
        expect(config[:label]).to eq('Sign in with Google')
      end

      it 'returns Google brand CSS classes' do
        expect(config[:css_class]).to include('bg-white')
        expect(config[:css_class]).to include('text-gray-700')
      end

      it 'returns an SVG icon' do
        expect(config[:icon]).to include('<svg')
        expect(config[:icon]).to include('</svg>')
      end
    end

    context 'when provider is github' do
      subject(:config) { helper.oauth_button_config(:github) }

      it 'returns GitHub label' do
        expect(config[:label]).to eq('Sign in with GitHub')
      end

      it 'returns GitHub brand CSS classes' do
        expect(config[:css_class]).to include('bg-[#24292f]')
        expect(config[:css_class]).to include('text-white')
      end

      it 'returns an SVG icon' do
        expect(config[:icon]).to include('<svg')
      end
    end

    context 'when provider is openid_connect' do
      subject(:config) { helper.oauth_button_config(:openid_connect) }

      before { stub_const('OIDC_PROVIDER_NAME', 'Authentik') }

      it 'returns label using OIDC provider name' do
        expect(config[:label]).to eq('Sign in with Authentik')
      end

      it 'returns primary CSS class' do
        expect(config[:css_class]).to include('btn-primary')
      end

      it 'returns no icon' do
        expect(config[:icon]).to be_nil
      end
    end

    context 'when provider is unknown' do
      subject(:config) { helper.oauth_button_config(:some_provider) }

      it 'returns generic label' do
        expect(config[:label]).to eq('Sign in with SomeProvider')
      end

      it 'returns primary CSS class' do
        expect(config[:css_class]).to include('btn-primary')
      end

      it 'returns no icon' do
        expect(config[:icon]).to be_nil
      end
    end
  end

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

  describe '#point_speed' do
    context 'when speed is zero or negative' do
      it 'returns the original value for zero' do
        expect(helper.point_speed(0)).to eq(0)
      end

      it 'returns the original value for negative' do
        expect(helper.point_speed(-1)).to eq(-1)
      end
    end

    context 'when speed is positive (m/s)' do
      it 'converts m/s to km/h by default' do
        expect(helper.point_speed(10)).to eq(36.0)
      end

      it 'converts m/s to km/h when unit is km' do
        expect(helper.point_speed(10, 'km')).to eq(36.0)
      end

      it 'converts m/s to mph when unit is mi' do
        expect(helper.point_speed(10, 'mi')).to eq(22.4)
      end

      it 'handles string input' do
        expect(helper.point_speed('10', 'km')).to eq(36.0)
      end
    end
  end

  describe '#speed_label' do
    it 'returns km/h by default' do
      expect(helper.speed_label).to eq('km/h')
    end

    it 'returns km/h when unit is km' do
      expect(helper.speed_label('km')).to eq('km/h')
    end

    it 'returns mph when unit is mi' do
      expect(helper.speed_label('mi')).to eq('mph')
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

      context 'when called with query params' do
        let(:params) { { start_at: '2025-01-01T00:00', end_at: '2025-12-31T23:59' } }

        context 'when preferred version is v1' do
          before do
            user.settings['maps'] = { 'preferred_version' => 'v1' }
            user.save
          end

          it 'returns map_v1_path with query params' do
            expect(helper.preferred_map_path(params)).to eq(helper.map_v1_path(params))
          end
        end

        context 'when preferred version is v2' do
          before do
            user.settings['maps'] = { 'preferred_version' => 'v2' }
            user.save
          end

          it 'returns map_v2_path with query params' do
            expect(helper.preferred_map_path(params)).to eq(helper.map_v2_path(params))
          end
        end
      end
    end
  end
end
