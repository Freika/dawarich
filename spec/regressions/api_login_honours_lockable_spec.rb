# frozen_string_literal: true

require 'rails_helper'

# Regression: the API email/password login must honour Devise lockable, like the
# web (Warden) path — count failed attempts and refuse a locked account.
RSpec.describe 'API login honours Devise lockable', type: :request do
  let!(:user) { create(:user, email: 'lock@example.com', password: 'secret123456') }

  it 'increments failed_attempts on a wrong API password' do
    expect do
      post '/api/v1/auth/login', params: { email: 'lock@example.com', password: 'wrong' }
    end.to change { user.reload.failed_attempts }.by(1)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses a locked account even with the correct password' do
    user.lock_access!(send_instructions: false)

    post '/api/v1/auth/login', params: { email: 'lock@example.com', password: 'secret123456' }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)).not_to have_key('api_key')
  end
end
