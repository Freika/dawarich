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
    end

    describe 'PATCH /update' do
      it 'updates email settings with checkbox value' do
        patch settings_general_path, params: { digest_emails_enabled: '0' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['digest_emails_enabled']).to eq(false)
      end

      it 'enables email settings' do
        patch settings_general_path, params: { digest_emails_enabled: '1' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['digest_emails_enabled']).to eq(true)
      end

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
