# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sidekiq Web POST over plain HTTP', type: :request do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    sign_in create(:user, :admin)
  end

  it 'does not forbid a POST without Sec-Fetch-Site when Origin matches the app' do
    post '/sidekiq/retries', headers: { 'Origin' => 'http://www.example.com' }

    expect(response).not_to have_http_status(:forbidden)
  end

  it 'forbids a POST without Sec-Fetch-Site when Origin is another site' do
    post '/sidekiq/retries', headers: { 'Origin' => 'http://evil.example' }

    expect(response).to have_http_status(:forbidden)
  end
end
