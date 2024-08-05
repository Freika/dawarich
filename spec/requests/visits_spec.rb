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

    context 'with confirmed visits' do
      let!(:confirmed_visits) { create_list(:visit, 3, user:, status: :confirmed) }

      it 'returns confirmed visits' do
        get visits_url

        expect(@controller.instance_variable_get(:@visits).map do |v|
                 v[:visits]
               end.flatten).to match_array(confirmed_visits)
      end
    end

    context 'with suggested visits' do
      let!(:suggested_visits) { create_list(:visit, 3, user:, status: :suggested) }

      it 'does not return suggested visits' do
        get visits_url

        expect(@controller.instance_variable_get(:@visits).map do |v|
                 v[:visits]
               end.flatten).not_to include(suggested_visits)
      end

      it 'returns suggested visits' do
        get visits_url, params: { status: 'suggested' }

        expect(@controller.instance_variable_get(:@visits).map do |v|
                 v[:visits]
               end.flatten).to match_array(suggested_visits)
      end
    end

    context 'with declined visits' do
      let!(:declined_visits) { create_list(:visit, 3, user:, status: :declined) }

      it 'does not return declined visits' do
        get visits_url

        expect(@controller.instance_variable_get(:@visits).map do |v|
                 v[:visits]
               end.flatten).not_to include(declined_visits)
      end

      it 'returns declined visits' do
        get visits_url, params: { status: 'declined' }

        expect(@controller.instance_variable_get(:@visits).map do |v|
                 v[:visits]
               end.flatten).to match_array(declined_visits)
      end
    end

    context 'with suggested visits' do
      let!(:suggested_visits) { create_list(:visit, 3, user:, status: :suggested) }

      it 'does not return suggested visits' do
        get visits_url

        expect(@controller.instance_variable_get(:@visits).map do |v|
                 v[:visits]
               end.flatten).not_to include(suggested_visits)
      end

      it 'returns suggested visits' do
        get visits_url, params: { status: 'suggested' }

        expect(@controller.instance_variable_get(:@visits).map do |v|
                 v[:visits]
               end.flatten).to match_array(suggested_visits)
      end
    end
  end

  describe 'PATCH /update' do
    context 'with valid parameters' do
      let(:visit) { create(:visit, user:, status: :suggested) }

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
