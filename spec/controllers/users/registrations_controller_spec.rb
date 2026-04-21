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
    context 'when bucketed as legacy_trial' do
      before do
        allow_any_instance_of(Signup::BucketVariant).to receive(:call).and_return('legacy_trial')
      end

      it 'creates user with status trial, signup_variant legacy_trial, subscription_source paddle' do
        post :create, params: valid_params

        user = User.find_by(email: unique_email)
        expect(user).to be_present
        expect(user.status).to eq('trial')
        expect(user.signup_variant).to eq('legacy_trial')
        expect(user.subscription_source).to eq('paddle')
      end
    end

    context 'when bucketed as reverse_trial' do
      before do
        allow_any_instance_of(Signup::BucketVariant).to receive(:call).and_return('reverse_trial')
      end

      it 'creates user with status pending_payment, signup_variant reverse_trial, subscription_source none' do
        post :create, params: valid_params

        user = User.find_by(email: unique_email)
        expect(user).to be_present
        expect(user.status).to eq('pending_payment')
        expect(user.signup_variant).to eq('reverse_trial')
        expect(user.subscription_source).to eq('none')
      end

      it 'redirects to Manager checkout URL with reverse_trial token' do
        post :create, params: valid_params

        user = User.find_by(email: unique_email)
        expect(response).to redirect_to(
          "#{MANAGER_URL}/checkout?token=#{user.generate_subscription_token(variant: 'reverse_trial')}"
        )
      end

      it 'does not schedule trial emails' do
        expect do
          post :create, params: valid_params
        end.not_to have_enqueued_job(Users::MailerSendingJob)
      end
    end
  end
end
