# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Points', type: :request do
  let!(:user) { create(:user) }
  let!(:points) do
    (1..15).map do |i|
      create(:point, user:, timestamp: 1.day.ago + i.minutes)
    end
  end
  let(:point_params) do
    {
      locations: [
        {
          geometry: { type: 'Point', coordinates: [1.0, 1.0] },
          properties: { timestamp: '2025-01-17T21:03:01Z' }
        }
      ]
    }
  end

  describe 'GET /index' do
    context 'when regular version of points is requested' do
      it 'renders a successful response' do
        get api_v1_points_url(api_key: user.api_key)

        expect(response).to be_successful
      end

      it 'returns a list of points' do
        get api_v1_points_url(api_key: user.api_key)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.size).to eq(15)
      end

      it 'returns a list of points with pagination' do
        get api_v1_points_url(api_key: user.api_key, page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.size).to eq(5)
      end

      it 'returns a list of points with pagination headers' do
        get api_v1_points_url(api_key: user.api_key, page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        expect(response.headers['X-Current-Page']).to eq('2')
        expect(response.headers['X-Total-Pages']).to eq('2')
      end
    end

    context 'when slim version of points is requested' do
      it 'renders a successful response' do
        get api_v1_points_url(api_key: user.api_key, slim: 'true')

        expect(response).to be_successful
      end

      it 'returns a list of points' do
        get api_v1_points_url(api_key: user.api_key, slim: 'true')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.size).to eq(15)
      end

      it 'returns a list of points with pagination' do
        get api_v1_points_url(api_key: user.api_key, slim: 'true', page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.size).to eq(5)
      end

      it 'returns a list of points with pagination headers' do
        get api_v1_points_url(api_key: user.api_key, slim: 'true', page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        expect(response.headers['X-Current-Page']).to eq('2')
        expect(response.headers['X-Total-Pages']).to eq('2')
      end

      it 'returns a list of points with slim attributes' do
        get api_v1_points_url(api_key: user.api_key, slim: 'true')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        json_response.each do |point|
          expect(point.keys).to eq(%w[id latitude longitude timestamp velocity country_name])
        end
      end
    end

    context 'when order param is provided' do
      it 'returns points in ascending order' do
        get api_v1_points_url(api_key: user.api_key, order: 'asc')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.first['timestamp']).to be < json_response.last['timestamp']
      end

      it 'returns points in descending order' do
        get api_v1_points_url(api_key: user.api_key, order: 'desc')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.first['timestamp']).to be > json_response.last['timestamp']
      end
    end
  end

  describe 'POST /create' do
    it 'returns a successful response' do
      post "/api/v1/points?api_key=#{user.api_key}", params: point_params

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)['data']

      expect(json_response.size).to be_positive
      expect(json_response.first['latitude']).to eq(1.0)
      expect(json_response.first['longitude']).to eq(1.0)
      expect(json_response.first['timestamp']).to be_an_instance_of(Integer)
    end

    context 'when user is inactive' do
      before do
        user.update(status: :inactive, active_until: 1.day.ago)
      end

      it 'returns an unauthorized response' do
        post "/api/v1/points?api_key=#{user.api_key}", params: point_params

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PUT /update' do
    it 'returns a successful response' do
      put "/api/v1/points/#{points.first.id}?api_key=#{user.api_key}",
          params: { point: { latitude: 1.0, longitude: 1.1 } }

      expect(response).to have_http_status(:success)
    end

    context 'when user is inactive' do
      before do
        user.update(status: :inactive, active_until: 1.day.ago)
      end

      it 'returns an unauthorized response' do
        put "/api/v1/points/#{points.first.id}?api_key=#{user.api_key}",
            params: { point: { latitude: 1.0, longitude: 1.1 } }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /destroy' do
    it 'returns a successful response' do
      delete "/api/v1/points/#{points.first.id}?api_key=#{user.api_key}"

      expect(response).to have_http_status(:success)
    end

    context 'when user is inactive' do
      before do
        user.update(status: :inactive, active_until: 1.day.ago)
      end

      it 'returns an unauthorized response' do
        delete "/api/v1/points/#{points.first.id}?api_key=#{user.api_key}"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /bulk_destroy' do
    let(:point_ids) { points.first(5).map(&:id) }

    it 'returns a successful response' do
      delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
             params: { point_ids: }

      expect(response).to have_http_status(:ok)
    end

    it 'deletes multiple points' do
      expect do
        delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
               params: { point_ids: }
      end.to change { user.points.count }.by(-5)
    end

    it 'returns the count of deleted points' do
      delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
             params: { point_ids: }

      json_response = JSON.parse(response.body)

      expect(json_response['message']).to eq('Points were successfully destroyed')
      expect(json_response['count']).to eq(5)
    end

    it 'only deletes points belonging to the current user' do
      other_user = create(:user)
      other_points = create_list(:point, 3, user: other_user)
      all_point_ids = point_ids + other_points.map(&:id)

      expect do
        delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
               params: { point_ids: all_point_ids }
      end.to change { user.points.count }.by(-5)
                                         .and change { other_user.points.count }.by(0)
    end

    context 'when no point_ids are provided' do
      it 'returns success with zero count' do
        delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
               params: { point_ids: [] }

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['count']).to eq(0)
      end
    end

    context 'when point_ids parameter is missing' do
      it 'returns an error' do
        delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}"

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('No points selected')
      end
    end

    context 'when user is inactive' do
      before do
        user.update(status: :inactive, active_until: 1.day.ago)
      end

      it 'returns an unauthorized response' do
        delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
               params: { point_ids: }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not delete any points' do
        expect do
          delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
                 params: { point_ids: }
        end.not_to(change { user.points.count })
      end
    end

    context 'when deleting all user points' do
      it 'successfully deletes all points' do
        all_point_ids = points.map(&:id)

        expect do
          delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
                 params: { point_ids: all_point_ids }
        end.to change { user.points.count }.from(15).to(0)
      end
    end

    context 'when some point_ids do not exist' do
      it 'deletes only existing points' do
        non_existent_ids = [999_999, 888_888]
        mixed_ids = point_ids + non_existent_ids

        expect do
          delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
                 params: { point_ids: mixed_ids }
        end.to change { user.points.count }.by(-5)

        json_response = JSON.parse(response.body)
        expect(json_response['count']).to eq(5)
      end
    end
  end

  describe 'GET /index (archived param for data retention)' do
    context 'when user is on lite plan' do
      let!(:lite_user) do
        u = create(:user)
        u.update_columns(plan: User.plans[:lite])
        u
      end

      let!(:recent_point) do
        create(:point, user: lite_user, timestamp: 1.month.ago.to_i)
      end

      let!(:old_point) do
        create(:point, user: lite_user, timestamp: 13.months.ago.to_i)
      end

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'returns only archived points when archived=true' do
        get api_v1_points_url(api_key: lite_user.api_key, archived: 'true')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        returned_ids = json_response.map { |p| p['id'] }

        expect(returned_ids).to include(old_point.id)
        expect(returned_ids).not_to include(recent_point.id)
      end

      it 'returns only recent points when archived is not set' do
        get api_v1_points_url(api_key: lite_user.api_key)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        returned_ids = json_response.map { |p| p['id'] }

        expect(returned_ids).to include(recent_point.id)
        expect(returned_ids).not_to include(old_point.id)
      end
    end

    context 'when user is on pro plan' do
      let!(:pro_user) do
        u = create(:user)
        u.update_columns(plan: User.plans[:pro])
        u
      end

      let!(:recent_point) do
        create(:point, user: pro_user, timestamp: 1.month.ago.to_i)
      end

      let!(:old_point) do
        create(:point, user: pro_user, timestamp: 13.months.ago.to_i)
      end

      it 'returns empty array when archived=true (no archived concept for Pro)' do
        get api_v1_points_url(api_key: pro_user.api_key, archived: 'true')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response).to eq([])
      end
    end

    context 'when user is a self-hoster' do
      let!(:self_hoster) { create(:user) }

      let!(:old_point) do
        create(:point, user: self_hoster, timestamp: 13.months.ago.to_i)
      end

      it 'returns empty array when archived=true (no archived concept for self-hosters)' do
        get api_v1_points_url(api_key: self_hoster.api_key, archived: 'true')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response).to eq([])
      end
    end
  end
end
