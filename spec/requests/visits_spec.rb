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

        expect(@controller.instance_variable_get(:@visits)).to match_array(confirmed_visits)
      end
    end

    context 'with suggested visits' do
      let!(:suggested_visits) { create_list(:visit, 3, user:, status: :suggested) }

      it 'does not return suggested visits' do
        get visits_url

        expect(@controller.instance_variable_get(:@visits)).not_to include(suggested_visits)
      end

      it 'returns suggested visits' do
        get visits_url, params: { status: 'suggested' }

        expect(@controller.instance_variable_get(:@visits)).to match_array(suggested_visits)
      end
    end

    context 'with declined visits' do
      let!(:declined_visits) { create_list(:visit, 3, user:, status: :declined) }

      it 'does not return declined visits' do
        get visits_url

        expect(@controller.instance_variable_get(:@visits)).not_to include(declined_visits)
      end

      it 'returns declined visits' do
        get visits_url, params: { status: 'declined' }

        expect(@controller.instance_variable_get(:@visits)).to match_array(declined_visits)
      end
    end
  end

  describe 'PATCH /bulk_update' do
    let!(:suggested_visits) { create_list(:visit, 3, user:, status: :suggested) }

    it 'confirms all suggested visits' do
      patch bulk_update_visits_url, params: { status: 'confirmed', source_status: 'suggested' }

      expect(suggested_visits.each(&:reload).map(&:status)).to all(eq('confirmed'))
      expect(response).to redirect_to(visits_path(status: 'suggested'))
      follow_redirect!
      expect(response.body).to include('3 visits confirmed.')
    end

    it 'declines all suggested visits' do
      patch bulk_update_visits_url, params: { status: 'declined', source_status: 'suggested' }

      expect(suggested_visits.each(&:reload).map(&:status)).to all(eq('declined'))
      expect(response).to redirect_to(visits_path(status: 'suggested'))
    end

    it 'does not affect visits of other users' do
      other_user = create(:user)
      other_visit = create(:visit, user: other_user, status: :suggested)

      patch bulk_update_visits_url, params: { status: 'confirmed', source_status: 'suggested' }

      expect(other_visit.reload.status).to eq('suggested')
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

      it 'redirects to the visits index page' do
        patch visit_url(visit), params: { visit: { status: :confirmed } }

        expect(response).to redirect_to(visits_url(status: :suggested))
      end

      it 'auto-names the visit from suggested place when confirming without name change' do
        place = create(:place, user:, name: 'Central Park')
        create(:place_visit, visit:, place:)

        patch visit_url(visit), params: { visit: { status: :confirmed } }

        expect(visit.reload.name).to eq('Central Park')
      end

      it 'keeps the original name when confirming if no suggested place exists' do
        visit.update!(name: 'My Visit')

        patch visit_url(visit), params: { visit: { status: :confirmed } }

        expect(visit.reload.name).to eq('My Visit')
      end
    end

    context 'with turbo_stream format' do
      let(:visit) { create(:visit, user:, status: :suggested) }

      it 'updates status and returns turbo_stream removing visit item' do
        patch visit_url(visit), params: { visit: { status: :confirmed } }, as: :turbo_stream

        expect(visit.reload.status).to eq('confirmed')
        expect_turbo_stream_response
        expect_turbo_stream_action('remove', "visit_item_#{visit.id}")
      end

      it 'sets visit name from place when place_id is provided' do
        place = create(:place, user:, name: 'Coffee Shop')
        patch visit_url(visit), params: { visit: { place_id: place.id } }, as: :turbo_stream

        expect(visit.reload.name).to eq('Coffee Shop')
        expect_turbo_stream_response
        expect_turbo_stream_action('replace', "visit_name_#{visit.id}")
      end

      it 'returns turbo_stream replace on non-status update' do
        patch visit_url(visit), params: { visit: { name: 'New Name' } }, as: :turbo_stream

        expect_turbo_stream_response
        expect_turbo_stream_action('replace', "visit_name_#{visit.id}")
      end
    end
  end
end
