# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Visits', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }
  let(:place) { create(:place) }
  let(:other_user) { create(:user) }
  let(:auth_headers) { { 'Authorization' => "Bearer #{api_key}" } }

  describe 'GET /api/v1/visits' do
    let!(:visit1) { create(:visit, user: user, place: place, started_at: 2.days.ago, ended_at: 1.day.ago) }
    let!(:visit2) { create(:visit, user: user, place: place, started_at: 4.days.ago, ended_at: 3.days.ago) }
    let!(:other_user_visit) { create(:visit, user: other_user, place: place) }

    context 'when requesting time-based visits' do
      let(:params) do
        {
          start_at: 5.days.ago.iso8601,
          end_at: Time.zone.now.iso8601
        }
      end

      it 'returns visits within the specified time range' do
        get '/api/v1/visits', params: params, headers: auth_headers

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response.size).to eq(2)
        expect(json_response.pluck('id')).to include(visit1.id, visit2.id)
      end

      it 'does not return visits from other users' do
        get '/api/v1/visits', params: params, headers: auth_headers

        json_response = JSON.parse(response.body)
        expect(json_response.pluck('id')).not_to include(other_user_visit.id)
      end
    end

    context 'when requesting area-based visits' do
      let(:place_inside) { create(:place, latitude: 50.0, longitude: 14.0) }
      let!(:visit_inside) { create(:visit, user: user, place: place_inside) }

      let(:params) do
        {
          selection: 'true',
          sw_lat: '49.0',
          sw_lng: '13.0',
          ne_lat: '51.0',
          ne_lng: '15.0'
        }
      end

      it 'returns visits within the specified area' do
        get '/api/v1/visits', params: params, headers: auth_headers

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response.pluck('id')).to include(visit_inside.id)
        expect(json_response.pluck('id')).not_to include(visit1.id, visit2.id)
      end
    end
  end

  describe 'PUT /api/v1/visits/:id' do
    let(:visit) { create(:visit, user:) }

    let(:valid_attributes) do
      {
        visit: {
          name: 'New name'
        }
      }
    end

    let(:invalid_attributes) do
      {
        visit: {
          name: nil
        }
      }
    end

    context 'with valid parameters' do
      it 'updates the requested visit' do
        put "/api/v1/visits/#{visit.id}", params: valid_attributes, headers: auth_headers

        expect(visit.reload.name).to eq('New name')
      end

      it 'renders a JSON response with the visit' do
        put "/api/v1/visits/#{visit.id}", params: valid_attributes, headers: auth_headers

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid parameters' do
      it 'renders a JSON response with errors for the visit' do
        put "/api/v1/visits/#{visit.id}", params: invalid_attributes, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/visits/merge' do
    let!(:visit1) { create(:visit, user: user, started_at: 2.days.ago, ended_at: 1.day.ago) }
    let!(:visit2) { create(:visit, user: user, started_at: 4.days.ago, ended_at: 3.days.ago) }
    let!(:other_user_visit) { create(:visit, user: other_user) }

    context 'with valid parameters' do
      let(:valid_merge_params) do
        {
          visit_ids: [visit1.id, visit2.id]
        }
      end

      it 'merges the specified visits' do
        # Mock the service to avoid dealing with complex merging logic in the test
        merge_service = instance_double(Visits::MergeService)
        merged_visit = create(:visit, user: user)

        expect(Visits::MergeService).to receive(:new).with(kind_of(ActiveRecord::Relation)).and_return(merge_service)
        expect(merge_service).to receive(:call).and_return(merged_visit)

        post '/api/v1/visits/merge', params: valid_merge_params, headers: auth_headers

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid parameters' do
      it 'returns an error when fewer than 2 visits are specified' do
        post '/api/v1/visits/merge', params: { visit_ids: [visit1.id] }, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('At least 2 visits must be selected')
      end

      it 'returns an error when not all visits are found' do
        post '/api/v1/visits/merge', params: { visit_ids: [visit1.id, 999_999] }, headers: auth_headers

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('not found')
      end

      it 'returns an error when trying to merge other user visits' do
        post '/api/v1/visits/merge', params: { visit_ids: [visit1.id, other_user_visit.id] }, headers: auth_headers

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('not found')
      end

      it 'returns an error when the merge fails' do
        merge_service = instance_double(Visits::MergeService)

        expect(Visits::MergeService).to receive(:new).with(kind_of(ActiveRecord::Relation)).and_return(merge_service)
        expect(merge_service).to receive(:call).and_return(nil)
        expect(merge_service).to receive(:errors).and_return(['Failed to merge visits'])

        post '/api/v1/visits/merge', params: { visit_ids: [visit1.id, visit2.id] }, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Failed to merge visits')
      end
    end
  end

  describe 'POST /api/v1/visits/bulk_update' do
    let!(:visit1) { create(:visit, user: user, status: 'suggested') }
    let!(:visit2) { create(:visit, user: user, status: 'suggested') }
    let!(:other_user_visit) { create(:visit, user: other_user, status: 'suggested') }
    let(:bulk_update_service) { instance_double(Visits::BulkUpdate) }

    context 'with valid parameters' do
      let(:valid_update_params) do
        {
          visit_ids: [visit1.id, visit2.id],
          status: 'confirmed'
        }
      end

      it 'updates the status of specified visits' do
        expect(Visits::BulkUpdate).to receive(:new)
          .with(user, kind_of(Array), 'confirmed')
          .and_return(bulk_update_service)
        expect(bulk_update_service).to receive(:call).and_return({ count: 2 })

        post '/api/v1/visits/bulk_update', params: valid_update_params, headers: auth_headers

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['updated_count']).to eq(2)
      end
    end

    context 'with invalid parameters' do
      let(:invalid_update_params) do
        {
          visit_ids: [visit1.id, visit2.id],
          status: 'invalid_status'
        }
      end

      it 'returns an error when the update fails' do
        expect(Visits::BulkUpdate).to receive(:new)
          .with(user, kind_of(Array), 'invalid_status')
          .and_return(bulk_update_service)
        expect(bulk_update_service).to receive(:call).and_return(nil)
        expect(bulk_update_service).to receive(:errors).and_return(['Invalid status'])

        post '/api/v1/visits/bulk_update', params: invalid_update_params, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Invalid status')
      end
    end
  end
end
