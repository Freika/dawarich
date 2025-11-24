# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/places', type: :request do
  let(:user) { create(:user) }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})

    sign_in user
  end

  describe 'GET /index' do
    it 'renders a successful response' do
      get places_url

      expect(response).to be_successful
    end
  end

  describe 'DELETE /destroy' do
    let!(:place) { create(:place, user:) }
    let!(:visit) { create(:visit, place:, user:) }

    it 'destroys the requested place' do
      expect do
        delete place_url(place)
      end.to change(Place, :count).by(-1)
    end

    it 'redirects to the places list' do
      delete place_url(place)

      expect(response).to redirect_to(places_url)
    end
  end
end
