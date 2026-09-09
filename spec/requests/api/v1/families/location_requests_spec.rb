# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Families::LocationRequests', type: :request do
  let(:requester) { create(:user) }
  let(:target) { create(:user) }
  let(:family) { create(:family, creator: requester) }
  let!(:requester_membership) { create(:family_membership, user: requester, family: family, role: :owner) }
  let!(:target_membership) { create(:family_membership, user: target, family: family, role: :member) }

  describe 'POST /api/v1/families/location_requests' do
    it 'creates a request for a non-sharing member' do
      post '/api/v1/families/location_requests',
           params: { target_user_id: target.id },
           headers: { 'Authorization' => "Bearer #{requester.api_key}" }

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['request']['target_user_id']).to eq(target.id)
      expect(Family::LocationRequest.active.count).to eq(1)
    end

    it 'returns 429 while the cooldown is active' do
      create(:family_location_request, requester: requester, target_user: target, family: family)

      post '/api/v1/families/location_requests',
           params: { target_user_id: target.id },
           headers: { 'Authorization' => "Bearer #{requester.api_key}" }

      expect(response).to have_http_status(:too_many_requests)
      expect(JSON.parse(response.body)['message']).to be_present
    end

    it 'returns 422 when the target already shares' do
      target.update_family_location_sharing!(true, duration: 'permanent')

      post '/api/v1/families/location_requests',
           params: { target_user_id: target.id },
           headers: { 'Authorization' => "Bearer #{requester.api_key}" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 404 for a target outside the family' do
      outsider = create(:user)

      post '/api/v1/families/location_requests',
           params: { target_user_id: outsider.id },
           headers: { 'Authorization' => "Bearer #{requester.api_key}" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/families/location_requests/:id/accept' do
    let!(:request_record) do
      create(:family_location_request, requester: requester, target_user: target, family: family)
    end

    it 'accepts and enables sharing' do
      post "/api/v1/families/location_requests/#{request_record.id}/accept",
           params: { duration: '1h' },
           headers: { 'Authorization' => "Bearer #{target.api_key}" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('accepted')
      expect(target.reload.family_sharing_enabled?).to be true
    end

    it 'forbids accepting someone else\'s request' do
      post "/api/v1/families/location_requests/#{request_record.id}/accept",
           headers: { 'Authorization' => "Bearer #{requester.api_key}" }

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for an unknown request id' do
      post '/api/v1/families/location_requests/0/accept',
           headers: { 'Authorization' => "Bearer #{target.api_key}" }

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 for an expired request' do
      request_record.update!(expires_at: 1.hour.ago)

      post "/api/v1/families/location_requests/#{request_record.id}/accept",
           headers: { 'Authorization' => "Bearer #{target.api_key}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(target.reload.family_sharing_enabled?).to be false
    end
  end

  describe 'POST /api/v1/families/location_requests/:id/decline' do
    let!(:request_record) do
      create(:family_location_request, requester: requester, target_user: target, family: family)
    end

    it 'declines the request' do
      post "/api/v1/families/location_requests/#{request_record.id}/decline",
           headers: { 'Authorization' => "Bearer #{target.api_key}" }

      expect(response).to have_http_status(:ok)
      expect(request_record.reload).to be_declined
    end

    it 'returns 422 for an already responded request' do
      request_record.update!(status: :declined, responded_at: Time.current)

      post "/api/v1/families/location_requests/#{request_record.id}/decline",
           headers: { 'Authorization' => "Bearer #{target.api_key}" }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'when the Entitlement has lapsed' do
    let!(:pending_request) do
      create(:family_location_request, requester: requester, target_user: target, family: family)
    end

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      requester.update!(plan: :family, status: :inactive, active_until: 1.day.ago)
      target.update!(plan: :lite, status: :inactive, active_until: 1.day.ago)
      family.update!(access_until: 1.day.ago)
    end

    it 'refuses to create a location request' do
      post '/api/v1/families/location_requests',
           params: { target_user_id: target.id },
           headers: { 'Authorization' => "Bearer #{requester.api_key}" }

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses to accept a pending location request' do
      post "/api/v1/families/location_requests/#{pending_request.id}/accept",
           headers: { 'Authorization' => "Bearer #{target.api_key}" }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
