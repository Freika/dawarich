# frozen_string_literal: true

require 'rails_helper'

# Affiliate attribution runs server-side because the default Cloud variant
# (reverse_trial) redirects to Manager for checkout immediately after signup —
# a browser-side po('customers','signup') call would never fire for those users.
RSpec.describe 'Users::Registrations Partnero attribution', type: :request do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
    stub_const('MANAGER_URL', 'https://manager.example.com')
  end

  let(:unique_email) { "referred-#{SecureRandom.hex(4)}@example.com" }
  let(:valid_params) do
    {
      user: {
        email: unique_email,
        password: 'password123456',
        password_confirmation: 'password123456'
      }
    }
  end

  context 'when the visitor arrived through an affiliate link' do
    it 'attributes the created user to the referring partner' do
      get new_user_registration_path(via: 'PARTNER123')

      expect { post user_registration_path, params: valid_params }
        .to have_enqueued_job(Partnero::CustomerSignupJob)
        .with(instance_of(Integer), 'PARTNER123')
    end

    it 'attributes the job to the user that was actually created' do
      get new_user_registration_path(via: 'PARTNER123')
      post user_registration_path, params: valid_params

      user = User.find_by(email: unique_email)
      expect(user).to be_present
      expect(Partnero::CustomerSignupJob)
        .to have_been_enqueued.with(user.id, 'PARTNER123')
    end

    it 'spends the referral once so a later signup is not double-credited' do
      get new_user_registration_path(via: 'PARTNER123')
      post user_registration_path, params: valid_params

      second = { user: { email: "other-#{SecureRandom.hex(4)}@example.com",
                         password: 'password123456',
                         password_confirmation: 'password123456' } }

      expect { post user_registration_path, params: second }
        .not_to have_enqueued_job(Partnero::CustomerSignupJob)
    end
  end

  context 'when the visitor arrived directly' do
    it 'creates the user but enqueues no attribution job' do
      get new_user_registration_path

      expect { post user_registration_path, params: valid_params }
        .to change(User, :count).by(1)

      expect(Partnero::CustomerSignupJob).not_to have_been_enqueued
    end
  end

  context 'when the instance is self-hosted' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    it 'ignores the referral entirely' do
      get new_user_registration_path(via: 'PARTNER123')

      expect { post user_registration_path, params: valid_params }
        .not_to have_enqueued_job(Partnero::CustomerSignupJob)
    end

    it 'never loads PartneroJS, so self-hosted instances make no third-party call' do
      get new_user_registration_path(via: 'PARTNER123')

      expect(response.body).not_to include('partnero')
    end
  end

  describe 'OAuth signups' do
    before(:all) do
      Rails.application.routes.append do
        devise_scope :user do
          get 'users/auth/google_oauth2/callback', to: 'users/omniauth_callbacks#google_oauth2'
        end
      end
      Rails.application.reload_routes!
    end

    after(:all) { Rails.application.reload_routes! }

    before do
      Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
      mock_google_auth(email: unique_email)
    end

    def oauth_callback
      Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:google_oauth2]
      get '/users/auth/google_oauth2/callback'
    end

    it 'attributes a first-time Google signup to the referring partner' do
      get new_user_registration_path(via: 'PARTNER123')

      expect { oauth_callback }
        .to change(User, :count).by(1)
        .and have_enqueued_job(Partnero::CustomerSignupJob).with(instance_of(Integer), 'PARTNER123')
    end

    it 'does not re-credit the partner when an existing user logs in again' do
      get new_user_registration_path(via: 'PARTNER123')
      oauth_callback

      get new_user_registration_path(via: 'PARTNER123')

      expect { oauth_callback }.not_to change(User, :count)
      expect(Partnero::CustomerSignupJob).to have_been_enqueued.exactly(:once)
    end
  end

  describe 'the tracking snippet on Cloud' do
    it 'loads PartneroJS for the configured program' do
      get new_user_registration_path

      expect(response.body).to include('app.partnero.com/js/universal.js')
      expect(response.body).to include("po('program', '1NNVU1NU', 'load')")
    end
  end
end
