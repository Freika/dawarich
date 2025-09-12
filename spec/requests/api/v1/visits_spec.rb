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

  describe 'POST /api/v1/visits' do
    let(:valid_create_params) do
      {
        visit: {
          name: 'Test Visit',
          latitude: 52.52,
          longitude: 13.405,
          started_at: '2023-12-01T10:00:00Z',
          ended_at: '2023-12-01T12:00:00Z'
        }
      }
    end

    context 'with valid parameters' do
      let(:existing_place) { create(:place, latitude: 52.52, longitude: 13.405) }

      it 'creates a new visit' do
        expect do
          post '/api/v1/visits', params: valid_create_params, headers: auth_headers
        end.to change { user.visits.count }.by(1)

        expect(response).to have_http_status(:ok)
      end

      it 'creates a visit with correct attributes' do
        post '/api/v1/visits', params: valid_create_params, headers: auth_headers

        json_response = JSON.parse(response.body)
        expect(json_response['name']).to eq('Test Visit')
        expect(json_response['status']).to eq('confirmed')
        expect(json_response['duration']).to eq(120) # 2 hours in minutes
        expect(json_response['place']['latitude']).to eq(52.52)
        expect(json_response['place']['longitude']).to eq(13.405)
      end

      it 'creates a place for the visit' do
        expect do
          post '/api/v1/visits', params: valid_create_params, headers: auth_headers
        end.to change { Place.count }.by(1)

        created_place = Place.last
        expect(created_place.name).to eq('Test Visit')
        expect(created_place.latitude).to eq(52.52)
        expect(created_place.longitude).to eq(13.405)
        expect(created_place.source).to eq('manual')
      end

      it 'reuses existing place when coordinates are exactly the same' do
        create(:visit, user: user, place: existing_place)

        expect do
          post '/api/v1/visits', params: valid_create_params, headers: auth_headers
        end.not_to(change { Place.count })

        json_response = JSON.parse(response.body)
        expect(json_response['place']['id']).to eq(existing_place.id)
      end
    end

    context 'with invalid parameters' do
      context 'when required fields are missing' do
        let(:missing_name_params) do
          valid_create_params.deep_merge(visit: { name: '' })
        end

        it 'returns unprocessable entity status' do
          post '/api/v1/visits', params: missing_name_params, headers: auth_headers

          expect(response).to have_http_status(:unprocessable_content)
        end

        it 'returns error message' do
          post '/api/v1/visits', params: missing_name_params, headers: auth_headers

          json_response = JSON.parse(response.body)

          expect(json_response['error']).to eq('Failed to create visit')
        end

        it 'does not create a visit' do
          expect do
            post '/api/v1/visits', params: missing_name_params, headers: auth_headers
          end.not_to(change { Visit.count })
        end
      end
    end

    context 'with invalid API key' do
      let(:invalid_auth_headers) { { 'Authorization' => 'Bearer invalid-key' } }

      it 'returns unauthorized status' do
        post '/api/v1/visits', params: valid_create_params, headers: invalid_auth_headers

        expect(response).to have_http_status(:unauthorized)
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

        expect(response).to have_http_status(:unprocessable_content)
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

        expect(response).to have_http_status(:unprocessable_content)
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

        expect(response).to have_http_status(:unprocessable_content)
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

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Invalid status')
      end
    end
  end

  describe 'DELETE /api/v1/visits/:id' do
    let!(:visit) { create(:visit, user: user, place: place) }
    let!(:other_user_visit) { create(:visit, user: other_user, place: place) }

    context 'when visit exists and belongs to current user' do
      it 'deletes the visit' do
        expect do
          delete "/api/v1/visits/#{visit.id}", headers: auth_headers
        end.to change { user.visits.count }.by(-1)

        expect(response).to have_http_status(:no_content)
      end

      it 'removes the visit from the database' do
        delete "/api/v1/visits/#{visit.id}", headers: auth_headers

        expect { visit.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when visit does not exist' do
      it 'returns not found status' do
        delete '/api/v1/visits/999999', headers: auth_headers

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Visit not found')
      end
    end

    context 'when visit belongs to another user' do
      it 'returns not found status' do
        delete "/api/v1/visits/#{other_user_visit.id}", headers: auth_headers

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Visit not found')
      end

      it 'does not delete the visit' do
        expect do
          delete "/api/v1/visits/#{other_user_visit.id}", headers: auth_headers
        end.not_to(change { Visit.count })
      end
    end

    context 'with invalid API key' do
      let(:invalid_auth_headers) { { 'Authorization' => 'Bearer invalid-key' } }

      it 'returns unauthorized status' do
        delete "/api/v1/visits/#{visit.id}", headers: invalid_auth_headers

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
