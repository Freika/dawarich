# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/register', type: :request do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:valid_params) do
    { email: 'new@example.com', password: 'secret123456', password_confirmation: 'secret123456' }
  end

  it 'creates a user in pending_payment status with an api_key' do
    expect do
      post '/api/v1/auth/register', params: valid_params
    end.to change(User, :count).by(1)

    user = User.find_by(email: 'new@example.com')
    expect(user.status).to eq('pending_payment')
    expect(user.subscription_source).to eq('none')
    expect(user.api_key).to be_present
  end

  it 'returns 201 with user_id, email, api_key' do
    post '/api/v1/auth/register', params: valid_params
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body).to include('user_id', 'email', 'api_key', 'status')
    expect(body['status']).to eq('pending_payment')
  end

  it 'rejects duplicate emails with 422' do
    create(:user, email: 'new@example.com')
    post '/api/v1/auth/register', params: valid_params
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'rejects weak passwords' do
    post '/api/v1/auth/register', params: valid_params.merge(password: 'x', password_confirmation: 'x')
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'does not send welcome emails (trial not started)' do
    ActiveJob::Base.queue_adapter = :test
    post '/api/v1/auth/register', params: valid_params
    expect(Users::MailerSendingJob).not_to have_been_enqueued
  end

  it 'enqueues the Manager creation webhook so cloud users sync to Manager' do
    ActiveJob::Base.queue_adapter = :test

    expect { post '/api/v1/auth/register', params: valid_params }
      .to have_enqueued_job(Users::CreationWebhookJob).with(an_instance_of(Integer))
  end

  it 'does not enqueue the Manager creation webhook on validation failure' do
    ActiveJob::Base.queue_adapter = :test

    expect do
      post '/api/v1/auth/register', params: valid_params.merge(password: 'x', password_confirmation: 'x')
    end.not_to have_enqueued_job(Users::CreationWebhookJob)
  end

  it 'normalizes email casing/whitespace on signup so login round-trips' do
    post '/api/v1/auth/register',
         params: valid_params.merge(email: '  Mixed@Example.COM  ')
    expect(response).to have_http_status(:created)

    user = User.find_by(email: 'mixed@example.com')
    expect(user).to be_present

    post '/api/v1/auth/login',
         params: { email: 'mixed@example.com', password: 'secret123456' }
    expect(response).to have_http_status(:ok)
  end

  context 'on a self-hosted instance' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    it 'creates a user in active status (not pending_payment)' do
      expect do
        post '/api/v1/auth/register', params: valid_params
      end.to change(User, :count).by(1)

      user = User.find_by(email: 'new@example.com')
      expect(user.status).to eq('active')
      expect(user.plan).to eq('pro')
      expect(user.active_until).to be > 900.years.from_now
      expect(user.api_key).to be_present
    end

    it 'returns 201 with active status in the response body' do
      post '/api/v1/auth/register', params: valid_params
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('active')
    end

    it 'does not enqueue the Manager creation webhook (no Manager exists self-hosted)' do
      ActiveJob::Base.queue_adapter = :test

      expect { post '/api/v1/auth/register', params: valid_params }
        .not_to have_enqueued_job(Users::CreationWebhookJob)
    end
  end

  describe 'registering with a family invitation token' do
    let(:owner) { create(:user, plan: :family, status: :trial, active_until: 7.days.from_now) }
    let(:family) { create(:family, creator: owner) }
    let!(:owner_membership) { create(:family_membership, :owner, user: owner, family: family) }
    let(:invitation) do
      create(:family_invitation, family: family, invited_by: owner, email: 'invitee@example.com')
    end

    let(:invitee_params) do
      {
        email: invitation.email,
        password: 'secret123456',
        password_confirmation: 'secret123456',
        invitation_token: invitation.token
      }
    end

    it 'joins the invitee to the family' do
      expect { post '/api/v1/auth/register', params: invitee_params }
        .to change { family.reload.members.count }.from(1).to(2)
    end

    it 'activates the invitee rather than demanding payment' do
      post '/api/v1/auth/register', params: invitee_params

      expect(User.find_by(email: invitation.email)).to be_active
    end

    it 'reports the family plan the invitee inherits' do
      post '/api/v1/auth/register', params: invitee_params

      expect(JSON.parse(response.body)['effective_plan']).to eq('family')
    end

    it 'puts the invitee on the pro plan' do
      post '/api/v1/auth/register', params: invitee_params

      expect(User.find_by(email: invitation.email)).to be_pro
    end

    it 'marks the invitation accepted' do
      post '/api/v1/auth/register', params: invitee_params

      expect(invitation.reload).to be_accepted
    end

    it 'still requires payment when the token is unusable' do
      invitation.update!(status: :cancelled)

      post '/api/v1/auth/register', params: invitee_params

      expect(User.find_by(email: invitation.email)).to be_pending_payment
    end

    it 'still requires payment when the token belongs to a different email' do
      post '/api/v1/auth/register', params: invitee_params.merge(email: 'someone.else@example.com')

      expect(User.find_by(email: 'someone.else@example.com')).to be_pending_payment
    end
  end
end
