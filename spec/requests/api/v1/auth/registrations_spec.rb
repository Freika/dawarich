require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/register', type: :request do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:valid_params) do
    { email: 'new@example.com', password: 'secret123', password_confirmation: 'secret123' }
  end

  it 'creates a user in pending_payment status with an api_key' do
    expect {
      post '/api/v1/auth/register', params: valid_params
    }.to change(User, :count).by(1)

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
end
