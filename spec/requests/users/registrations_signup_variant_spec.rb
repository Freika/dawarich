# frozen_string_literal: true

require 'rails_helper'

# Exercises the reverse_trial signup variant through the full HTTP stack. On
# Cloud, reverse_trial is the default (and only) variant assigned by
# `Signup::BucketVariant` during `build_resource`, before the record has an id.
RSpec.describe 'Users::Registrations signup variant', type: :request do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(false)
    allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
    stub_const('MANAGER_URL', 'https://manager.example.com')
  end

  let(:unique_email) { "variant-user-#{SecureRandom.hex(4)}@example.com" }
  let(:valid_params) do
    {
      user: {
        email: unique_email,
        password: 'password123456',
        password_confirmation: 'password123456'
      }
    }
  end

  describe 'POST /users' do
    context 'on Cloud (reverse_trial is the default variant)' do
      it 'places the user in pending_payment with subscription_source=none' do
        post user_registration_path, params: valid_params

        user = User.find_by(email: unique_email)
        expect(user.signup_variant).to eq('reverse_trial')
        expect(user.status).to eq('pending_payment')
        expect(user.subscription_source).to eq('none')
      end

      it 'redirects to Manager checkout with a reverse_trial token' do
        post user_registration_path, params: valid_params

        user = User.find_by(email: unique_email)

        # Token is non-deterministic (per-call `jti` and `exp`), so assert
        # the URL shape and decode the token to verify the variant claim
        # rather than comparing against a freshly-generated token string.
        expect(response).to have_http_status(:redirect)
        location = response.location
        expect(location).to start_with("#{MANAGER_URL}/checkout?token=")

        token = location.split('token=', 2).last
        decoded = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY'), true, { algorithm: 'HS256' }).first
        expect(decoded['user_id']).to eq(user.id)
        expect(decoded['variant']).to eq('reverse_trial')
      end

      it 'does not enqueue trial onboarding emails' do
        expect { post user_registration_path, params: valid_params }
          .not_to have_enqueued_job(Users::MailerSendingJob)
      end

      it 'enqueues the Manager creation webhook exactly once' do
        expect { post user_registration_path, params: valid_params }
          .to have_enqueued_job(Users::CreationWebhookJob).exactly(:once)
      end
    end

    context 'when the submitted params fail validation' do
      it 'returns 422 and does not create the user (invalid email)' do
        post user_registration_path, params: {
          user: { email: 'not-an-email', password: 'password123456', password_confirmation: 'password123456' }
        }

        expect(User.find_by(email: 'not-an-email')).to be_nil
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('email')
      end

      it 'returns 422 and does not create the user (password too short)' do
        post user_registration_path, params: {
          user: {
            email: "short-pw-#{SecureRandom.hex(4)}@example.com",
            password: '123',
            password_confirmation: '123'
          }
        }

        expect(User.where("email LIKE 'short-pw-%'").count).to eq(0)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'does not redirect to Manager checkout when validation fails' do
        post user_registration_path, params: {
          user: { email: 'bad', password: '1', password_confirmation: '1' }
        }

        expect(response.location.to_s).not_to include('manager.example.com/checkout')
      end
    end
  end
end
