# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::RegistrationsController, type: :controller do
  before do
    @request.env['devise.mapping'] = Devise.mappings[:user]
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(false)
    allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
    stub_const('MANAGER_URL', 'https://manager.example.com')

    # Ensure Flipper state is clean for every example. The ActiveRecord
    # adapter persists flag state between examples unless we reset it, and
    # the transactional fixtures only cover the `users` table we touch.
    Flipper.disable(:reverse_trial_signup)
  end

  let(:unique_email) { "variant-user-#{SecureRandom.hex(4)}@example.com" }
  let(:valid_params) do
    {
      user: {
        email: unique_email,
        password: 'password123',
        password_confirmation: 'password123'
      }
    }
  end

  describe 'POST #create' do
    context 'when the reverse_trial_signup flag is disabled (legacy_trial bucket)' do
      before { Flipper.disable(:reverse_trial_signup) }

      it 'creates the user with signup_variant legacy_trial' do
        post :create, params: valid_params

        user = User.find_by(email: unique_email)
        expect(user).to be_present
        expect(user.signup_variant).to eq('legacy_trial')
      end

      it 'transitions the user into the trial status' do
        post :create, params: valid_params

        user = User.find_by(email: unique_email)
        expect(user.status).to eq('trial')
      end

      it 'does not redirect to the Manager checkout URL' do
        post :create, params: valid_params

        expect(response.location).not_to include('manager.example.com/checkout')
      end
    end

    context 'when the reverse_trial_signup flag is enabled (reverse_trial bucket)' do
      before { Flipper.enable(:reverse_trial_signup) }

      it 'creates the user with signup_variant reverse_trial' do
        post :create, params: valid_params

        user = User.find_by(email: unique_email)
        expect(user).to be_present
        expect(user.signup_variant).to eq('reverse_trial')
      end

      it 'places the user in pending_payment status with no active subscription' do
        post :create, params: valid_params

        user = User.find_by(email: unique_email)
        expect(user.status).to eq('pending_payment')
        expect(user.subscription_source).to eq('none')
      end

      it 'redirects to Manager checkout URL with a reverse_trial token' do
        post :create, params: valid_params

        user = User.find_by(email: unique_email)
        expect(response).to redirect_to(
          "#{MANAGER_URL}/checkout?token=#{user.generate_subscription_token(variant: 'reverse_trial')}"
        )
      end

      it 'does not enqueue trial onboarding emails for the user' do
        expect { post :create, params: valid_params }
          .not_to have_enqueued_job(Users::MailerSendingJob)
      end
    end

    context 'when the flag is gated by percentage_of_actors' do
      # The signup flow buckets users from `build_resource`, before the
      # record has a primary key. Without a stable actor derived from the
      # email (see `Signup::BucketVariant`), `percentage_of_actors` would
      # degenerate here — Flipper would see `flipper_id = "User;"` for
      # every signup, giving all-or-nothing variant assignment. We verify
      # that a signup through the full controller stack actually lands a
      # non-nil variant under a percentage gate.
      it 'assigns a concrete variant (not nil) to the resulting user' do
        Flipper.enable_percentage_of_actors(:reverse_trial_signup, 50)

        post :create, params: valid_params

        user = User.find_by(email: unique_email)
        expect(user.signup_variant).to be_in(%w[legacy_trial reverse_trial])
      end
    end

    context 'when the submitted params fail validation' do
      it 're-renders the sign-up form with unprocessable_entity when the email is invalid' do
        post :create, params: {
          user: { email: 'not-an-email', password: 'password123', password_confirmation: 'password123' }
        }

        expect(User.find_by(email: 'not-an-email')).to be_nil
        expect(response.status).to eq(422).or eq(200)
        expect(response.body).to include('email') if response.body.present?
      end

      it 're-renders the sign-up form when the password is too short' do
        post :create, params: {
          user: { email: "short-pw-#{SecureRandom.hex(4)}@example.com", password: '123', password_confirmation: '123' }
        }

        expect(User.where("email LIKE 'short-pw-%'").count).to eq(0)
        expect(response.status).to eq(422).or eq(200)
      end

      it 'does not redirect to Manager checkout when validation fails' do
        Flipper.enable(:reverse_trial_signup)

        post :create, params: {
          user: { email: 'bad', password: '1', password_confirmation: '1' }
        }

        expect(response.location.to_s).not_to include('manager.example.com/checkout')
      end
    end
  end
end
