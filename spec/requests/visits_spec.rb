# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/visits', type: :request do
  let(:user) { create(:user) }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
    sign_in user
  end

  describe 'GET /index' do
    it 'renders a successful response' do
      get visits_url

      expect(response).to be_successful
    end
  end

  describe 'PATCH /update' do
    context 'with valid parameters' do
      let(:visit) { create(:visit, user:, status: :pending) }

      it 'confirms the requested visit' do
        patch visit_url(visit), params: { visit: { status: :confirmed } }

        expect(visit.reload.status).to eq('confirmed')
      end

      it 'rejects the requested visit' do
        patch visit_url(visit), params: { visit: { status: :declined } }

        expect(visit.reload.status).to eq('declined')
      end

      it 'redirects to the visit index page' do
        patch visit_url(visit), params: { visit: { status: :confirmed } }

        expect(response).to redirect_to(visits_url)
      end
    end
  end
end
