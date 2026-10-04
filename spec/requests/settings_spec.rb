# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings', type: :request do
  context 'A11 account security' do
    around do |example|
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end

    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    it 'rotates only the current actor key with the source redirect contract' do
      other = create(:user, email: 'a11rest-other@dawarich.test')
      other_before = other.attributes
      shapes = [
        ['plain', 'text/html', nil],
        ['turbo', 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml', 'http://www.example.com/users/edit'],
        ['referer', 'text/html', 'http://www.example.com/stats'],
        ['invalid_resource', 'text/html', nil], ['legacy_invalid_email', 'text/html', nil],
        ['dirty_settings', 'text/html', nil], ['legacy_uppercase_invalid_email', 'text/html', nil],
        ['legacy_padded_valid_email', 'text/html', nil]
      ]
      shapes.each_with_index do |(kind, accept, referer), index|
        aggregate_failures(kind) do
          user = create(:user, email: "a11rest-key-#{index}@dawarich.test", password: 'a11rest-password-42')
          client = ActionDispatch::Integration::Session.new(Rails.application)
          client.get('/users/sign_in')
          token = Nokogiri::HTML5(client.response.body).at_css('meta[name="csrf-token"]')['content']
          client.post('/users/sign_in', params: { authenticity_token: token,
                                                  user: { email: user.email, password: 'a11rest-password-42' } })
          expect(client.response.status).to eq(303)
          user.update_column(:email, '') if kind == 'invalid_resource'
          user.update_column(:email, 'invalid') if kind == 'legacy_invalid_email'
          user.update_column(:email, 'INVALID') if kind == 'legacy_uppercase_invalid_email'
          if kind == 'legacy_padded_valid_email'
            user.update_column(:email, " A11REST-LEGACY-#{index}@DAWARICH.TEST ")
            user.update_columns(reset_password_token: "a11rest-legacy-reset-#{index}",
                                reset_password_sent_at: 1.hour.ago)
          end
          if kind == 'dirty_settings'
            user.update_column(:settings,
                               user.settings.merge('immich_url' => 'https://immich.a11rest.test///'))
          end
          client.get('/users/edit')
          token = Nokogiri::HTML5(client.response.body).at_css('meta[name="csrf-token"]')['content']
          before = user.reload.attributes
          client.post('/settings/generate_api_key', params: '', headers: {
            'CONTENT_TYPE' => 'application/x-www-form-urlencoded', 'Accept' => accept,
                        'X-CSRF-Token' => token, 'Referer' => referer
          }.compact)
          expect(client.response.status).to eq(302)
          expect(client.response.location).to eq(referer || 'http://www.example.com/')
          after = user.reload.attributes
          expect(other.reload.attributes == other_before).to be(true)
          if %w[invalid_resource legacy_uppercase_invalid_email].include?(kind)
            expect(after == before).to be(true)
            probe = ActionDispatch::Integration::Session.new(Rails.application)
            probe.get('/api/v1/users/me', params: { api_key: before['api_key'] })
            expect(probe.response.status).to eq(200)
            probe.get('/api/v1/users/me', headers: { 'Authorization' => "Bearer #{before['api_key']}" })
            expect(probe.response.status).to eq(200)
            next
          end

          expect(user.api_key.match?(/\A[0-9a-f]{64}\z/)).to be(true)
          expect(user.api_key == before['api_key']).to be(false)
          ignored = %w[api_key updated_at]
          ignored << 'settings' if kind == 'dirty_settings'
          if kind == 'legacy_padded_valid_email'
            ignored.concat(%w[email reset_password_token reset_password_sent_at])
            expect(user.email).to eq("a11rest-legacy-#{index}@dawarich.test")
            expect(user.reset_password_token).to be_nil
            expect(user.reset_password_sent_at).to be_nil
          end
          expect(after.except(*ignored) == before.except(*ignored)).to be(true)
          expect(user.settings['immich_url']).to eq('https://immich.a11rest.test') if kind == 'dirty_settings'
          probe = ActionDispatch::Integration::Session.new(Rails.application)
          probe.get('/api/v1/users/me', params: { api_key: before['api_key'] })
          expect(probe.response.status).to eq(401)
          probe.get('/api/v1/users/me', params: { api_key: user.api_key })
          expect(probe.response.status).to eq(200)
          probe.get('/api/v1/users/me', headers: { 'Authorization' => "Bearer #{before['api_key']}" })
          expect(probe.response.status).to eq(401)
          probe.get('/api/v1/users/me', headers: { 'Authorization' => "Bearer #{user.api_key}" })
          expect(probe.response.status).to eq(200)
        end
      end
    end
  end

  describe 'GET /theme' do
    let(:params) { { theme: 'light' } }

    context 'when user is not signed in' do
      it 'redirects to the sign in page' do
        get '/settings/theme', params: params
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is signed in' do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      it 'updates the user theme' do
        get '/settings/theme', params: params
        expect(user.reload.theme).to eq('light')
      end

      it 'redirects to the root path' do
        get '/settings/theme', params: params
        expect(response).to redirect_to(root_path)
      end

      context 'when theme is dark' do
        let(:params) { { theme: 'dark' } }

        it 'updates the user theme' do
          get '/settings/theme', params: params
          expect(user.reload.theme).to eq('dark')
        end
      end
    end
  end

  describe 'POST /generate_api_key' do
    context 'when user is not signed in' do
      it 'redirects to the sign in page' do
        post '/settings/generate_api_key'

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is signed in' do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      it 'generates an API key for the user' do
        expect { post '/settings/generate_api_key' }.to(change { user.reload.api_key })
      end

      it 'redirects back' do
        post '/settings/generate_api_key'

        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'GET /settings/users' do
    let!(:user) { create(:user, admin: true) }

    before do
      sign_in user
    end

    context 'when self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end

      it 'returns http success' do
        get '/settings/users'

        expect(response).to have_http_status(:success)
      end
    end

    context 'when not self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'redirects to root path' do
        get '/settings/users'

        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'PATCH /settings/changelog_consent' do
    context 'when user is not signed in' do
      it 'redirects to the sign in page' do
        patch '/settings/changelog_consent', params: { decision: 'granted' }
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is signed in' do
      let(:user) { create(:user) }

      before { sign_in user }

      it 'records granted and responds with a turbo stream replacing the indicator' do
        patch '/settings/changelog_consent', params: { decision: 'granted' },
              headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

        expect(response).to have_http_status(:ok)
        expect(user.reload.changelog_consent_granted?).to be(true)
        expect(response.body).to include('version-indicator')
      end

      it 'records declined' do
        patch '/settings/changelog_consent', params: { decision: 'declined' },
              headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

        expect(user.reload.changelog_consent_declined?).to be(true)
      end

      it 'lets a user reverse an earlier choice' do
        user.update!(changelog_consent: :granted)

        patch '/settings/changelog_consent', params: { decision: 'declined' },
              headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

        expect(user.reload.changelog_consent_declined?).to be(true)
      end

      it 'rejects an invalid decision without changing state' do
        patch '/settings/changelog_consent', params: { decision: 'bogus' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(user.reload.changelog_consent).to be_nil
      end
    end
  end

  describe 'GET /settings/general' do
    let(:user) { create(:user) }

    before { sign_in user }

    it 'renders the opt-in control when notices are off' do
      get settings_general_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('changelog-consent-setting')
      expect(response.body).to include('Turn on notices')
    end

    it 'renders the opt-out control once notices are on' do
      user.update!(changelog_consent: :granted)

      get settings_general_index_path

      expect(response.body).to include('Turn off notices')
    end

    it 'hides the notices panel on cloud' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

      get settings_general_index_path

      expect(response.body).not_to include('changelog-consent-setting')
      expect(response.body).not_to include("What's New notices")
    end
  end
end
