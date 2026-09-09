# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API locale stability', type: :request do
  let(:user) { create(:user, settings: { 'locale' => 'de' }) }

  it 'answers in the default locale despite a German Accept-Language header' do
    delete '/api/v1/points/bulk_destroy',
           headers: { 'Authorization' => "Bearer #{user.api_key}", 'Accept-Language' => 'de-DE,de;q=0.9' }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to eq('No points selected')
  end

  it 'ignores an explicit locale parameter' do
    delete '/api/v1/points/bulk_destroy',
           params: { locale: 'de' },
           headers: { 'Authorization' => "Bearer #{user.api_key}" }

    expect(response.parsed_body['error']).to eq('No points selected')
  end

  it 'does not persist a locale preference from an API request' do
    expect do
      delete '/api/v1/points/bulk_destroy',
             params: { locale: 'de' },
             headers: { 'Authorization' => "Bearer #{user.api_key}" }
    end.not_to(change { user.reload.settings })
  end
end
