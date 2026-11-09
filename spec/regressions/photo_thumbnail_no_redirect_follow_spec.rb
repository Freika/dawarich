# frozen_string_literal: true

require 'rails_helper'

# Regression: the server-side thumbnail fetch must not follow redirects, so a
# save-time-validated integration host cannot 302 the request into internal space.
RSpec.describe 'Photo thumbnail does not follow redirects', type: :request do
  let(:user) { create(:user, :with_immich_integration) }

  it 'answers with an error and never requests the redirect target' do
    stub_request(:get, 'https://immich.example.com/api/assets/asset-1/thumbnail?size=preview')
      .to_return(status: 302, headers: { 'Location' => 'http://169.254.169.254/latest/meta-data' })
    target = stub_request(:any, %r{\Ahttp://169\.254\.169\.254})

    get '/api/v1/photos/asset-1/thumbnail', params: { api_key: user.api_key, source: 'immich' }

    expect(response).to have_http_status(:bad_gateway)
    expect(target).not_to have_been_requested
  end
end
