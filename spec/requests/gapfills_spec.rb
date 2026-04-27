# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/gapfills', type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:start_point) { create(:point, user: user, lonlat: 'POINT(13.3888 52.5170)', timestamp: 1_000_000) }
  let(:end_point) { create(:point, user: user, lonlat: 'POINT(13.4050 52.5200)', timestamp: 1_001_000) }

  let(:brouter_response) do
    {
      'type' => 'FeatureCollection',
      'features' => [
        {
          'type' => 'Feature',
          'geometry' => {
            'type' => 'LineString',
            'coordinates' => [
              [13.3888, 52.5170],
              [13.3920, 52.5180],
              [13.3950, 52.5185],
              [13.4050, 52.5200]
            ]
          }
        }
      ]
    }.to_json
  end

  before do
    allow(DawarichSettings).to receive(:gapfill_enabled?).and_return(true)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('BROUTER_URL').and_return('https://brouter.test/brouter')
    stub_request(:get, /brouter/)
      .to_return(status: 200, body: brouter_response, headers: { 'Content-Type' => 'application/json' })
  end

  context 'when user is plan-restricted' do
    let(:lite_user) { create(:user, :lite_plan) }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      sign_in lite_user
    end

    it 'rejects preview with forbidden' do
      post preview_gapfills_url, params: {
        start_point_id: start_point.id, end_point_id: end_point.id, mode: 'Car'
      }, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects create with a redirect' do
      post gapfills_url, params: {
        start_point_id: start_point.id, end_point_id: end_point.id, mode: 'Car'
      }

      expect(flash[:alert]).to match(/Pro plan/)
    end
  end

  context 'when gapfill is disabled' do
    before do
      allow(DawarichSettings).to receive(:gapfill_enabled?).and_return(false)
      sign_in user
    end

    it 'redirects preview with an alert' do
      post preview_gapfills_url, params: {
        start_point_id: start_point.id, end_point_id: end_point.id, mode: 'Car'
      }

      expect(response).to redirect_to(map_v2_path)
      expect(flash[:alert]).to match(/BROUTER_URL/)
    end

    it 'returns forbidden for preview as JSON' do
      post preview_gapfills_url, params: {
        start_point_id: start_point.id, end_point_id: end_point.id, mode: 'Car'
      }, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'redirects create with an alert' do
      post gapfills_url, params: {
        start_point_id: start_point.id, end_point_id: end_point.id, mode: 'Car'
      }

      expect(response).to redirect_to(map_v2_path)
      expect(flash[:alert]).to match(/BROUTER_URL/)
    end
  end

  describe 'POST /gapfills/preview' do
    context 'when user is not logged in' do
      it 'redirects to the login page' do
        post preview_gapfills_url, params: {
          start_point_id: start_point.id, end_point_id: end_point.id, mode: 'Car'
        }
        expect(response).to redirect_to(new_user_session_url)
      end
    end

    context 'when user is logged in' do
      before { sign_in user }

      it 'returns coordinates as JSON' do
        post preview_gapfills_url, params: {
          start_point_id: start_point.id, end_point_id: end_point.id, mode: 'Car'
        }

        expect(response).to be_successful
        json = JSON.parse(response.body)
        expect(json['coordinates']).to be_an(Array)
        expect(json['coordinates'].size).to eq(4)
      end

      it 'returns 422 for invalid mode' do
        stub_request(:get, /brouter/).to_return(status: 200, body: brouter_response)

        post preview_gapfills_url, params: {
          start_point_id: start_point.id, end_point_id: end_point.id, mode: 'Helicopter'
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns 404 for another user\'s points' do
        other_point = create(:point, user: other_user)

        post preview_gapfills_url, params: {
          start_point_id: other_point.id, end_point_id: end_point.id, mode: 'Car'
        }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /gapfills' do
    context 'when user is not logged in' do
      it 'redirects to the login page' do
        post gapfills_url, params: {
          start_point_id: start_point.id, end_point_id: end_point.id, mode: 'Car'
        }
        expect(response).to redirect_to(new_user_session_url)
      end
    end

    context 'when user is logged in' do
      before { sign_in user }

      it 'creates inferred points' do
        expect do
          post gapfills_url, params: {
            start_point_id: start_point.id, end_point_id: end_point.id, mode: 'Car'
          }
        end.to change(Point.inferred_only, :count).by(2)
      end

      it 'redirects with a flash message for HTML format' do
        post gapfills_url, params: {
          start_point_id: start_point.id, end_point_id: end_point.id, mode: 'Car'
        }
        expect(response).to redirect_to(map_v2_path)
        expect(flash[:notice]).to match(/Added \d+ inferred points/)
      end
    end
  end
end
