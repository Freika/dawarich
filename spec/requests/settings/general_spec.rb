# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'settings/general', type: :request do
  context 'when user is authenticated' do
    let!(:user) { create(:user, settings: {}) }

    before do
      sign_in user
    end

    describe 'GET /index' do
      it 'returns a success response' do
        get settings_general_index_url

        expect(response).to be_successful
      end

      it 'renders both digest toggles and the email-digests anchor' do
        get settings_general_index_url

        expect(response.body).to include('id="email-digests"')
        expect(response.body).to include('name="monthly_digest_emails_enabled"')
        expect(response.body).to include('name="yearly_digest_emails_enabled"')
      end
    end

    describe 'PATCH /update' do
      it 'disables news emails setting' do
        patch settings_general_path, params: { news_emails_enabled: '0' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['news_emails_enabled']).to eq(false)
      end

      it 'enables news emails setting' do
        patch settings_general_path, params: { news_emails_enabled: '1' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['news_emails_enabled']).to eq(true)
      end

      it 'updates monthly_digest_emails_enabled independently' do
        patch settings_general_path, params: { monthly_digest_emails_enabled: '0' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['monthly_digest_emails_enabled']).to eq(false)
      end

      it 'updates yearly_digest_emails_enabled independently' do
        patch settings_general_path, params: { yearly_digest_emails_enabled: '0' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['yearly_digest_emails_enabled']).to eq(false)
      end

      it 'updates both monthly and yearly digest settings' do
        patch settings_general_path, params: {
          monthly_digest_emails_enabled: '1',
          yearly_digest_emails_enabled: '0'
        }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['monthly_digest_emails_enabled']).to eq(true)
        expect(user.reload.settings['yearly_digest_emails_enabled']).to eq(false)
      end

      context 'when the user still has the legacy digest_emails_enabled key' do
        let!(:user) { create(:user, settings: { 'digest_emails_enabled' => false }) }

        it 'removes the legacy key once a new digest key is written, leaving only the new key' do
          patch settings_general_path, params: { monthly_digest_emails_enabled: '0' }

          settings = user.reload.settings
          expect(settings).to have_key('monthly_digest_emails_enabled')
          expect(settings['monthly_digest_emails_enabled']).to eq(false)
          expect(settings).not_to have_key('digest_emails_enabled')
        end

        it 'keeps the yearly default at true (via SafeSettings) after the legacy key is dropped' do
          patch settings_general_path, params: { monthly_digest_emails_enabled: '0' }

          user.reload
          expect(user.settings).not_to have_key('digest_emails_enabled')
          expect(user.settings).not_to have_key('yearly_digest_emails_enabled')
          expect(user.safe_settings.yearly_digest_emails_enabled?).to be true
        end
      end

      it 'updates timezone setting with valid timezone' do
        patch settings_general_path, params: { timezone: 'America/New_York' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['timezone']).to eq('America/New_York')
      end

      it 'persists timezone across page loads' do
        patch settings_general_path, params: { timezone: 'Asia/Tokyo' }
        user.reload

        expect(user.timezone).to eq('Asia/Tokyo')
      end

      it 'rejects invalid timezone' do
        patch settings_general_path, params: { timezone: 'Invalid/Timezone' }

        expect(user.reload.settings['timezone']).to be_nil
        # Should not save invalid timezone
      end

      it 'accepts UTC timezone' do
        patch settings_general_path, params: { timezone: 'UTC' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['timezone']).to eq('UTC')
      end
    end

    describe 'POST /verify_supporter' do
      context 'when email is blank' do
        it 'redirects with alert' do
          post settings_verify_supporter_path, params: { supporter_email: '' }

          expect(response).to redirect_to(settings_general_index_path)
          expect(flash[:alert]).to eq('Please enter an email address')
        end
      end

      context 'when email is a verified supporter' do
        before do
          allow_any_instance_of(Supporter::VerifyEmail).to receive(:call)
            .and_return({ supporter: true, platform: 'patreon' })
        end

        it 'saves email and redirects with success notice' do
          post settings_verify_supporter_path, params: { supporter_email: 'supporter@example.com' }

          expect(response).to redirect_to(settings_general_index_path)
          expect(flash[:notice]).to include('Verified!')
          expect(user.reload.settings['supporter_email']).to eq('supporter@example.com')
        end
      end

      context 'when email is not a supporter' do
        before do
          allow_any_instance_of(Supporter::VerifyEmail).to receive(:call)
            .and_return({ supporter: false })
        end

        it 'saves email and redirects with failure alert' do
          post settings_verify_supporter_path, params: { supporter_email: 'unknown@example.com' }

          expect(response).to redirect_to(settings_general_index_path)
          expect(flash[:alert]).to include('Email not found in supporter list')
          expect(user.reload.settings['supporter_email']).to eq('unknown@example.com')
        end
      end
    end
  end

  context 'when user is not authenticated' do
    it 'redirects to the sign in page' do
      get settings_general_index_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
