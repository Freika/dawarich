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
      let(:existing_place) { create(:place, user: user, latitude: 52.52, longitude: 13.405) }

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

      it 'confirms a suggested visit on edit so the change survives re-detection' do
        put "/api/v1/visits/#{visit.id}", params: valid_attributes, headers: auth_headers

        expect(visit.reload.status).to eq('confirmed')
      end

      it 'keeps an explicitly requested status' do
        put "/api/v1/visits/#{visit.id}",
            params: { visit: { name: 'New name', status: 'declined' } },
            headers: auth_headers

        expect(visit.reload.status).to eq('declined')
      end
    end

    context 'with invalid parameters' do
      it 'renders a JSON response with errors for the visit' do
        put "/api/v1/visits/#{visit.id}", params: invalid_attributes, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when updating name together with place_id' do
      let(:new_place) { create(:place, name: 'Coffee Shop', user: user) }

      it 'preserves the user-provided name instead of overwriting it with the place name' do
        put "/api/v1/visits/#{visit.id}",
            params: { visit: { name: 'Grandma house', place_id: new_place.id } },
            headers: auth_headers

        expect(visit.reload.name).to eq('Grandma house')
        expect(visit.place_id).to eq(new_place.id)
      end

      it 'falls back to the place name when the user clears the name field' do
        put "/api/v1/visits/#{visit.id}",
            params: { visit: { name: '', place_id: new_place.id } },
            headers: auth_headers

        expect(visit.reload.name).to eq('Coffee Shop')
        expect(visit.place_id).to eq(new_place.id)
      end

      it 'sets the visit name from the place when no name is provided' do
        put "/api/v1/visits/#{visit.id}",
            params: { visit: { place_id: new_place.id } },
            headers: auth_headers

        expect(visit.reload.name).to eq('Coffee Shop')
        expect(visit.place_id).to eq(new_place.id)
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

    context 'when the visit is already soft-deleted' do
      let!(:tombstone) { create(:visit, user: user, place: place, deleted_at: 1.day.ago) }

      it 'is not found by update' do
        patch "/api/v1/visits/#{tombstone.id}", params: { visit: { name: 'Ghost' } }.to_json,
              headers: auth_headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:not_found)
        expect(tombstone.reload.name).not_to eq('Ghost')
      end

      it 'is not found by destroy' do
        delete "/api/v1/visits/#{tombstone.id}", headers: auth_headers

        expect(response).to have_http_status(:not_found)
      end

      it 'cannot be merged' do
        alive = create(:visit, user: user, place: place)

        post '/api/v1/visits/merge', params: { visit_ids: [alive.id, tombstone.id] }.to_json,
             headers: auth_headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when visit exists and belongs to current user' do
      it 'soft-deletes the visit and responds with no content' do
        expect do
          delete "/api/v1/visits/#{visit.id}", headers: auth_headers
        end.to change { user.scoped_visits.count }.by(-1)

        expect(response).to have_http_status(:no_content)
      end

      it 'keeps the row as a tombstone hidden from readers' do
        delete "/api/v1/visits/#{visit.id}", headers: auth_headers

        expect(visit.reload.deleted_at).to be_present
        expect(Visit.active).not_to include(visit)
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
  describe 'POST /api/v1/visits/batch' do
    def visit_payload(offset_hours, name: 'Visit', status: 'suggested')
      {
        name: name,
        latitude: 52.52 + (offset_hours / 1000.0),
        longitude: 13.405 + (offset_hours / 1000.0),
        started_at: (Time.zone.parse('2023-12-01T10:00:00Z') + offset_hours.hours).iso8601,
        ended_at: (Time.zone.parse('2023-12-01T11:00:00Z') + offset_hours.hours).iso8601,
        status: status
      }
    end

    context 'with a valid batch' do
      let(:params) { { visits: [visit_payload(0, name: 'Home'), visit_payload(3, name: 'Office')] } }

      it 'creates every visit in one request' do
        expect do
          post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json
        end.to change { user.visits.count }.by(2)

        expect(response).to have_http_status(:ok)
      end

      it 'returns a result per submitted visit, in order, with its index' do
        post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json

        json_response = JSON.parse(response.body)
        expect(json_response['results'].pluck('index')).to eq([0, 1])
        expect(json_response['results'].pluck('status')).to eq(%w[created created])
        expect(json_response['results'].map { |result| result.dig('visit', 'name') }).to eq(%w[Home Office])
      end

      it 'reports created and failed counts' do
        post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json

        json_response = JSON.parse(response.body)
        expect(json_response['created_count']).to eq(2)
        expect(json_response['failed_count']).to eq(0)
      end

      it 'leaves place names unlocked for suggested visits' do
        post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json

        expect(user.places.reload.pluck(:name_locked_at)).to all(be_nil)
      end

      it 'assigns every visit to the authenticated user' do
        post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json

        expect(user.visits.count).to eq(2)
        expect(other_user.visits.count).to eq(0)
      end

      it 'does not duplicate visits when the same batch is replayed' do
        post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json

        expect do
          post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json
        end.not_to(change { user.visits.count })

        json_response = JSON.parse(response.body)
        expect(json_response['created_count']).to eq(0)
        expect(json_response['duplicate_count']).to eq(2)
      end
    end

    context 'when one visit in the batch is invalid' do
      let(:params) do
        { visits: [visit_payload(0, name: 'Home'), visit_payload(3, name: ''), visit_payload(6, name: 'Office')] }
      end

      it 'still creates the valid visits' do
        expect do
          post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json
        end.to change { user.visits.count }.by(2)
      end

      it 'marks only the offending index as failed' do
        post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json

        json_response = JSON.parse(response.body)
        expect(json_response['results'].pluck('status')).to eq(%w[created failed created])
        expect(json_response['results'][1]['error']).to be_present
        expect(json_response['created_count']).to eq(2)
        expect(json_response['failed_count']).to eq(1)
      end
    end

    context 'with an invalid envelope' do
      it 'rejects a missing visits key' do
        post '/api/v1/visits/batch', params: {}, headers: auth_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)['error']).to be_present
      end

      it 'rejects an empty visits array' do
        post '/api/v1/visits/batch', params: { visits: [] }, headers: auth_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'rejects a batch over the maximum size' do
        oversized = { visits: Array.new(Api::V1::VisitsController::BATCH_MAX + 1) { |i| visit_payload(i) } }

        expect do
          post '/api/v1/visits/batch', params: oversized, headers: auth_headers, as: :json
        end.not_to(change { Visit.count })

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['limit']).to eq(Api::V1::VisitsController::BATCH_MAX)
        expect(json_response['requested']).to eq(Api::V1::VisitsController::BATCH_MAX + 1)
      end
    end

    context 'when visits is not an array' do
      it 'rejects an object whose keys are permitted attributes' do
        post '/api/v1/visits/batch', params: { visits: { name: 'Home' } }, headers: auth_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'rejects a string' do
        post '/api/v1/visits/batch', params: { visits: 'Home' }, headers: auth_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when the batch contains a non-object element' do
      let(:params) { { visits: [visit_payload(0, name: 'Home'), 'junk', visit_payload(6, name: 'Office')] } }

      it 'keeps every submitted position addressable by index' do
        post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json

        json_response = JSON.parse(response.body)
        expect(json_response['results'].pluck('index')).to eq([0, 1, 2])
        expect(json_response['results'].pluck('status')).to eq(%w[created failed created])
      end

      it 'still creates the well-formed visits' do
        expect do
          post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json
        end.to change { user.visits.count }.by(2)
      end
    end

    context 'when a batch is replayed' do
      let(:params) { { visits: [visit_payload(0, name: 'Home')] } }

      it 'reports the second run as a duplicate rather than created' do
        post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json
        post '/api/v1/visits/batch', params: params, headers: auth_headers, as: :json

        json_response = JSON.parse(response.body)
        expect(json_response['results'].pluck('status')).to eq(%w[duplicate])
        expect(json_response['created_count']).to eq(0)
        expect(json_response['duplicate_count']).to eq(1)
      end

      it 'reports two identical entries in one batch as one created and one duplicate' do
        post '/api/v1/visits/batch',
             params: { visits: [visit_payload(0, name: 'Home'), visit_payload(0, name: 'Home')] },
             headers: auth_headers, as: :json

        json_response = JSON.parse(response.body)
        expect(json_response['created_count']).to eq(1)
        expect(json_response['duplicate_count']).to eq(1)
      end
    end

    context 'at the batch size boundary' do
      it 'accepts exactly BATCH_MAX visits' do
        payloads = Array.new(Api::V1::VisitsController::BATCH_MAX) { |i| visit_payload(i) }

        post '/api/v1/visits/batch', params: { visits: payloads }, headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['created_count']).to eq(Api::V1::VisitsController::BATCH_MAX)
      end
    end

    context 'when an entry ends before it starts' do
      it 'reports that entry as failed and keeps the rest' do
        bad = visit_payload(3).merge(started_at: '2023-12-05T10:00:00Z', ended_at: '2023-12-05T09:00:00Z')

        post '/api/v1/visits/batch',
             params: { visits: [visit_payload(0), bad] }, headers: auth_headers, as: :json

        json_response = JSON.parse(response.body)
        expect(json_response['results'].pluck('status')).to eq(%w[created failed])
        expect(json_response['failed_count']).to eq(1)
      end
    end

    context 'with a confirmed visit in the batch' do
      it 'still locks the place name' do
        post '/api/v1/visits/batch',
             params: { visits: [visit_payload(0, name: 'Home', status: 'confirmed')] },
             headers: auth_headers, as: :json

        expect(user.places.reload.pluck(:name_locked_at)).to all(be_present)
      end
    end

    context 'when many entries in one batch are rejected' do
      it 'reports at most one exception for the whole batch' do
        expect(ExceptionReporter).to receive(:call).at_most(:once)

        payloads = Array.new(5) { |i| visit_payload(i, name: '') }
        post '/api/v1/visits/batch', params: { visits: payloads }, headers: auth_headers, as: :json

        expect(JSON.parse(response.body)['failed_count']).to eq(5)
      end
    end

    context 'when reporting rejected entries' do
      it 'groups every batch under the same report regardless of how many failed' do
        reported = []
        allow(ExceptionReporter).to receive(:call) { |subject, _| reported << subject }

        post '/api/v1/visits/batch',
             params: { visits: Array.new(2) { |i| visit_payload(i, name: '') } },
             headers: auth_headers, as: :json
        post '/api/v1/visits/batch',
             params: { visits: Array.new(4) { |i| visit_payload(i + 10, name: '') } },
             headers: auth_headers, as: :json

        expect(reported.uniq.size).to eq(1)
      end
    end

    context 'when a replayed entry matches a visit the user deleted' do
      it 'reports it as a duplicate without handing back the tombstoned visit' do
        payload = visit_payload(0, name: 'Home')

        post '/api/v1/visits/batch', params: { visits: [payload] }, headers: auth_headers, as: :json
        user.visits.last.update!(deleted_at: Time.current)

        post '/api/v1/visits/batch', params: { visits: [payload] }, headers: auth_headers, as: :json

        result = JSON.parse(response.body)['results'].first
        expect(result['status']).to eq('duplicate')
        expect(result['visit']).to be_nil
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post '/api/v1/visits/batch', params: { visits: [visit_payload(0)] }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
