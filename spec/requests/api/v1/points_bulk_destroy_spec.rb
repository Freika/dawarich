# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::PointsController bulk_destroy', type: :request do
  describe 'DELETE /api/v1/points/bulk_destroy' do
    let(:user) { create(:user) }

    before do
      # Make sure the request is treated as authenticated API request
      allow_any_instance_of(ApiController).to receive(:current_api_user).and_return(user)
      allow_any_instance_of(ApiController).to receive(:authenticate_active_api_user!).and_return(true)
      allow_any_instance_of(ApiController).to receive(:require_write_api!).and_return(true)
    end

    it 'enqueues track recalculation jobs for affected tracks' do
      track1 = create(:track, user: user)
      track2 = create(:track, user: user)

      p1 = create(:point, user: user, track: track1)
      p2 = create(:point, user: user, track: track1)
      p3 = create(:point, user: user, track: track2)
      p4 = create(:point, user: user, track: nil)

      expect {
        delete '/api/v1/points/bulk_destroy', params: { point_ids: [p1.id, p2.id, p3.id, p4.id] }
      }.to have_enqueued_job(Tracks::RecalculateJob).with(track1.id)
        .and have_enqueued_job(Tracks::RecalculateJob).with(track2.id)

      expect(response).to have_http_status(:ok)
    end

    it 'does not enqueue jobs when no tracks are affected' do
      p1 = create(:point, user: user, track: nil)

      expect {
        delete '/api/v1/points/bulk_destroy', params: { point_ids: [p1.id] }
      }.not_to have_enqueued_job(Tracks::RecalculateJob)

      expect(response).to have_http_status(:ok)
    end
  end
end
