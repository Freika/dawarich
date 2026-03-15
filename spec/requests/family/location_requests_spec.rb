# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family::LocationRequests', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:family) { create(:family) }
  let(:owner) { family.creator }
  let(:target_user) { create(:user) }

  before do
    create(:family_membership, family: family, user: owner, role: :owner)
    create(:family_membership, family: family, user: target_user)
    allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(true)
  end

  describe 'POST /family/location_requests' do
    before { sign_in owner }

    it 'creates a location request' do
      expect do
        post family_location_requests_path, params: { target_user_id: target_user.id }
      end.to change(Family::LocationRequest, :count).by(1)
    end

    it 'redirects with flash on success' do
      post family_location_requests_path, params: { target_user_id: target_user.id }
      expect(response).to redirect_to(family_path)
      expect(flash[:notice]).to include('Location request sent')
    end

    it 'redirects with error when target is already sharing' do
      target_user.update_family_location_sharing!(true, duration: 'permanent')
      post family_location_requests_path, params: { target_user_id: target_user.id }
      expect(response).to redirect_to(family_path)
    end
  end

  describe 'GET /family/location_requests/:id' do
    let!(:request_record) do
      create(:family_location_request,
             requester: owner, target_user: target_user, family: family)
    end

    context 'when signed in as target user' do
      before { sign_in target_user }

      it 'shows the request detail page' do
        get family_location_request_path(request_record)
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when signed in as a different user' do
      before { sign_in owner }

      it 'redirects with error' do
        get family_location_request_path(request_record)
        expect(response).to redirect_to(family_path)
      end
    end
  end

  describe 'GET /family/location_requests/:id (non-family member)' do
    let!(:request_record) do
      create(:family_location_request,
             requester: owner, target_user: target_user, family: family)
    end
    let(:outsider) { create(:user) }

    context 'when signed in as a user not in any family' do
      before { sign_in outsider }

      it 'redirects with error' do
        get family_location_request_path(request_record)
        expect(response).to redirect_to(root_path)
      end
    end

    context 'when signed in as target user requesting non-existent record' do
      before { sign_in target_user }

      it 'returns 404 for non-existent record' do
        get family_location_request_path(id: 999_999)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PATCH /family/location_requests/:id/accept' do
    let!(:request_record) do
      create(:family_location_request,
             requester: owner, target_user: target_user, family: family,
             status: :pending, expires_at: 1.hour.from_now)
    end

    before { sign_in target_user }

    it 'accepts the request and enables sharing' do
      patch accept_family_location_request_path(request_record), params: { duration: '24h' }

      request_record.reload
      expect(request_record).to be_accepted
      expect(request_record.responded_at).to be_present
      expect(target_user.reload.family_sharing_enabled?).to be true
    end

    it 'redirects with success message' do
      patch accept_family_location_request_path(request_record), params: { duration: '24h' }
      expect(response).to redirect_to(family_path)
    end

    context 'when request is expired' do
      before { request_record.update!(expires_at: 1.hour.ago) }

      it 'does not accept and redirects with error' do
        patch accept_family_location_request_path(request_record), params: { duration: '24h' }
        expect(response).to redirect_to(family_path)
        expect(request_record.reload).to be_pending
      end
    end

    context 'when request is already responded to' do
      before { request_record.update!(status: :declined) }

      it 'redirects with error' do
        patch accept_family_location_request_path(request_record), params: { duration: '24h' }
        expect(response).to redirect_to(family_path)
      end
    end
  end

  describe 'PATCH /family/location_requests/:id/decline' do
    let!(:request_record) do
      create(:family_location_request,
             requester: owner, target_user: target_user, family: family,
             status: :pending, expires_at: 1.hour.from_now)
    end

    before { sign_in target_user }

    it 'declines the request' do
      patch decline_family_location_request_path(request_record)

      request_record.reload
      expect(request_record).to be_declined
      expect(request_record.responded_at).to be_present
    end

    it 'does not enable sharing' do
      patch decline_family_location_request_path(request_record)
      expect(target_user.reload.family_sharing_enabled?).to be false
    end
  end
end
