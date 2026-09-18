# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'settings/general', type: :request do
  context 'when user is authenticated' do
    let!(:user) { create(:user, settings: {}) }

    before do
      sign_in user
    end

    describe 'GET /index' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('SMTP_SERVER').and_return('smtp.example.com')
      end

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

      it 'shows a not-configured notice instead of preferences when SMTP is unset' do
        allow(ENV).to receive(:[]).with('SMTP_SERVER').and_return(nil)

        get settings_general_index_url

        expect(response.body).to include('Email sending via SMTP is not configured')
        expect(response.body).to include('https://dawarich.app/docs/self-hosting/configuration/smtp/')
        expect(response.body).not_to include('name="monthly_digest_emails_enabled"')
        expect(response.body).not_to include('name="news_emails_enabled"')
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

    describe 'POST /test_email' do
      around do |example|
        original_from = UsersMailer.default_params[:from]
        UsersMailer.default from: 'hi@dawarich.app'
        example.run
      ensure
        UsersMailer.default from: original_from
      end

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('SMTP_SERVER').and_return('smtp.example.com')
        ActionMailer::Base.deliveries.clear
      end

      it 'delivers a test email to the current user' do
        expect do
          post settings_test_email_path
        end.to change { ActionMailer::Base.deliveries.size }.by(1)

        expect(ActionMailer::Base.deliveries.last.to).to include(user.email)
        expect(response).to redirect_to(settings_general_index_path)
        expect(flash[:notice]).to include(user.email)
      end

      it 'shows an alert when SMTP is not configured' do
        allow(ENV).to receive(:[]).with('SMTP_SERVER').and_return(nil)

        post settings_test_email_path

        expect(ActionMailer::Base.deliveries).to be_empty
        expect(response).to redirect_to(settings_general_index_path)
        expect(flash[:alert]).to be_present
      end

      it 'shows an alert with the error when delivery fails' do
        allow_any_instance_of(Mail::Message).to receive(:deliver)
          .and_raise(Net::SMTPAuthenticationError.new('authentication failed'))

        post settings_test_email_path

        expect(response).to redirect_to(settings_general_index_path)
        expect(flash[:alert]).to include('Net::SMTPAuthenticationError')
      end

      it 'responds with turbo stream when requested' do
        post settings_test_email_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
        expect(response.body).to include(user.email)
      end

      it 'renders the button as a Turbo POST link' do
        get settings_general_index_path

        link = response.body.scan(/<a[^>]*settings\/general\/test_email[^>]*>/).first
        expect(link).to be_present
        expect(link).to include('data-turbo="true"')
        expect(link).to include('data-turbo-method="post"')
        expect(response.body).to include(
          '>Sends a test message to your account email to verify SMTP settings</span>'
        )
      end

      context 'when not self-hosted' do
        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        end

        it 'is not authorized' do
          post settings_test_email_path

          expect(ActionMailer::Base.deliveries).to be_empty
          expect(response).to redirect_to(root_path)
        end

        it 'does not render the test email button' do
          get settings_general_index_path

          expect(response.body).not_to include('test_email')
        end
      end
    end

    describe 'POST /verify_supporter' do
      context 'when both email and github username are blank' do
        it 'redirects with alert' do
          post settings_verify_supporter_path, params: { supporter_email: '', supporter_github_username: '' }

          expect(response).to redirect_to(settings_general_index_path)
          expect(flash[:alert]).to include('email address or GitHub username')
        end
      end

      context 'when github username is a verified supporter' do
        before do
          allow_any_instance_of(Supporter::VerifyGithubUsername).to receive(:call)
            .and_return({ supporter: true, platform: 'github' })
        end

        it 'saves the username and redirects with success notice' do
          post settings_verify_supporter_path, params: { supporter_github_username: 'octocat' }

          expect(response).to redirect_to(settings_general_index_path)
          expect(flash[:notice]).to include('Verified!')
          expect(user.reload.settings['supporter_github_username']).to eq('octocat')
        end
      end

      context 'when github username is not a supporter' do
        before do
          allow_any_instance_of(Supporter::VerifyEmail).to receive(:call).and_return({ supporter: false })
          allow_any_instance_of(Supporter::VerifyGithubUsername).to receive(:call).and_return({ supporter: false })
        end

        it 'saves the username and redirects with failure alert' do
          post settings_verify_supporter_path, params: { supporter_github_username: 'nobody' }

          expect(response).to redirect_to(settings_general_index_path)
          expect(flash[:alert]).to include('supporter list')
          expect(user.reload.settings['supporter_github_username']).to eq('nobody')
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
          expect(flash[:alert]).to include('supporter list')
          expect(user.reload.settings['supporter_email']).to eq('unknown@example.com')
        end
      end

      context 'when one field is submitted blank while the other was saved' do
        before do
          allow_any_instance_of(Supporter::VerifyEmail).to receive(:call).and_return({ supporter: false })
          allow_any_instance_of(Supporter::VerifyGithubUsername).to receive(:call).and_return({ supporter: false })
          user.update!(settings: user.settings.merge('supporter_email' => 'saved@example.com'))
        end

        it 'does not wipe the previously saved email' do
          post settings_verify_supporter_path, params: { supporter_email: '', supporter_github_username: 'octocat' }

          expect(user.reload.settings['supporter_email']).to eq('saved@example.com')
          expect(user.reload.settings['supporter_github_username']).to eq('octocat')
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
