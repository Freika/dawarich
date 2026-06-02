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
          expect(point.keys).to eq(%w[id latitude longitude timestamp velocity country_name tracker_id])
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

    context 'when user is inactive but active_until is in the future' do
      before do
        user.update(status: :inactive, active_until: 1.day.from_now)
      end

      it 'returns an unauthorized response' do
        post "/api/v1/points?api_key=#{user.api_key}", params: point_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is on lite plan' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        # update_columns bypasses the activate callback that resets plan to :pro
        user.update_column(:plan, User.plans[:lite])
      end

      it 'allows point creation (Lite users can create points)' do
        post "/api/v1/points?api_key=#{user.api_key}", params: point_params

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)['data']
        expect(json_response.size).to be_positive
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

    context 'when user is inactive but active_until is in the future' do
      before do
        user.update(status: :inactive, active_until: 1.day.from_now)
      end

      it 'returns an unauthorized response' do
        put "/api/v1/points/#{points.first.id}?api_key=#{user.api_key}",
            params: { point: { latitude: 1.0, longitude: 1.1 } }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is on lite plan' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        # update_columns bypasses the activate callback that resets plan to :pro
        user.update_column(:plan, User.plans[:lite])
      end

      it 'returns 403 with write_api_restricted error' do
        put "/api/v1/points/#{points.first.id}?api_key=#{user.api_key}",
            params: { point: { latitude: 1.0, longitude: 1.1 } }

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)['error']).to eq('write_api_restricted')
      end
    end
  end

  describe 'DELETE /destroy' do
    it 'returns a successful response' do
      delete "/api/v1/points/#{points.first.id}?api_key=#{user.api_key}"

      expect(response).to have_http_status(:success)
    end

    context 'when the point belongs to a track' do
      let(:track) { create(:track, user: user) }
      let!(:tracked_point) { create(:point, user: user, track: track) }

      it 'enqueues a recalculation job for the track' do
        expect do
          delete "/api/v1/points/#{tracked_point.id}?api_key=#{user.api_key}"
        end.to have_enqueued_job(Tracks::RecalculateJob).with(track.id)

        expect(response).to have_http_status(:success)
      end
    end

    context 'when the point has no track' do
      let!(:trackless_point) { create(:point, user: user, track: nil) }

      it 'does not enqueue a recalculation job' do
        expect do
          delete "/api/v1/points/#{trackless_point.id}?api_key=#{user.api_key}"
        end.not_to have_enqueued_job(Tracks::RecalculateJob)
      end
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

    context 'when user is inactive but active_until is in the future' do
      before do
        user.update(status: :inactive, active_until: 1.day.from_now)
      end

      it 'returns an unauthorized response' do
        delete "/api/v1/points/#{points.first.id}?api_key=#{user.api_key}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is on lite plan' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        # update_columns bypasses the activate callback that resets plan to :pro
        user.update_column(:plan, User.plans[:lite])
      end

      it 'returns 403 with write_api_restricted error' do
        delete "/api/v1/points/#{points.first.id}?api_key=#{user.api_key}"

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)['error']).to eq('write_api_restricted')
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

    context 'when deleted points belong to one or more tracks' do
      let(:track1) { create(:track, user: user) }
      let(:track2) { create(:track, user: user) }
      let!(:p1) { create(:point, user: user, track: track1) }
      let!(:p2) { create(:point, user: user, track: track1) }
      let!(:p3) { create(:point, user: user, track: track2) }
      let!(:p4) { create(:point, user: user, track: nil) }

      it 'enqueues a recalculation job for each distinct affected track' do
        expect do
          delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
                 params: { point_ids: [p1.id, p2.id, p3.id, p4.id] }
        end.to have_enqueued_job(Tracks::RecalculateJob).with(track1.id)
                                                        .and have_enqueued_job(Tracks::RecalculateJob).with(track2.id)

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when no deleted points belong to a track' do
      let!(:trackless) { create_list(:point, 2, user: user, track: nil) }

      it 'does not enqueue any recalculation jobs' do
        expect do
          delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
                 params: { point_ids: trackless.map(&:id) }
        end.not_to have_enqueued_job(Tracks::RecalculateJob)
      end
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

    context 'when user is inactive but active_until is in the future' do
      before do
        user.update(status: :inactive, active_until: 1.day.from_now)
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

    context 'when user is on lite plan' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        # update_columns bypasses the activate callback that resets plan to :pro
        user.update_column(:plan, User.plans[:lite])
      end

      it 'returns 403 with write_api_restricted error' do
        delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
               params: { point_ids: }

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)['error']).to eq('write_api_restricted')
      end

      it 'does not delete any points' do
        expect do
          delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
                 params: { point_ids: }
        end.not_to(change { user.points.count })
      end
    end

    context 'when more than BULK_DESTROY_MAX point_ids are submitted' do
      let(:oversized_ids) { (1..(Api::V1::PointsController::BULK_DESTROY_MAX + 1)).to_a }

      it 'returns 422 with the limit and requested counts' do
        expect do
          delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}",
                 params: { point_ids: oversized_ids }, as: :json
        end.not_to(change { user.points.count })

        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body)
        expect(body['limit']).to eq(Api::V1::PointsController::BULK_DESTROY_MAX)
        expect(body['requested']).to eq(oversized_ids.size)
      end
    end

    context 'when at least one point is deleted' do
      it 'enqueues Stats::CalculatingJob once per affected (year, month)' do
        # Two points in Jan 2025, one in Feb 2025 — expect 2 jobs (one per month).
        jan_a = create(:point, user:, timestamp: Time.zone.local(2025, 1, 10).to_i)
        jan_b = create(:point, user:, timestamp: Time.zone.local(2025, 1, 20).to_i)
        feb   = create(:point, user:, timestamp: Time.zone.local(2025, 2, 5).to_i)
        ids = [jan_a.id, jan_b.id, feb.id]

        expect do
          delete "/api/v1/points/bulk_destroy?api_key=#{user.api_key}", params: { point_ids: ids }
        end.to have_enqueued_job(Stats::CalculatingJob).exactly(2).times
      end
    end
  end

  describe 'GET /index (read API scoping for lite plan)' do
    context 'when user is on lite plan' do
      let!(:lite_user) do
        u = create(:user)
        # Bypass the activate callback that overrides plan
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

      it 'returns only points within the 12-month window' do
        get api_v1_points_url(api_key: lite_user.api_key)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        returned_ids = json_response.map { |p| p['id'] }

        expect(returned_ids).to include(recent_point.id)
        expect(returned_ids).not_to include(old_point.id)
      end

      it 'returns X-Total-Points-In-Range header with the unscoped count' do
        get api_v1_points_url(
          api_key: lite_user.api_key,
          start_at: 14.months.ago.to_i,
          end_at: Time.current.to_i
        )

        expect(response).to have_http_status(:ok)
        expect(response.headers['X-Total-Points-In-Range']).to eq('2')
        expect(response.headers['X-Scoped-Points']).to eq('1')
      end

      it 'cannot bypass the 12-month window via start_at param' do
        get api_v1_points_url(api_key: lite_user.api_key, start_at: 0)

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

      it 'returns all points regardless of age' do
        get api_v1_points_url(api_key: pro_user.api_key)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        returned_ids = json_response.map { |p| p['id'] }

        expect(returned_ids).to include(recent_point.id)
        expect(returned_ids).to include(old_point.id)
      end
    end

    context 'when on a self-hosted instance' do
      let!(:self_hosted_user) { create(:user) } # default plan is pro

      let!(:recent_point) do
        create(:point, user: self_hosted_user, timestamp: 1.month.ago.to_i)
      end

      let!(:old_point) do
        create(:point, user: self_hosted_user, timestamp: 13.months.ago.to_i)
      end

      it 'returns all points regardless of age' do
        get api_v1_points_url(api_key: self_hosted_user.api_key)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        returned_ids = json_response.map { |p| p['id'] }

        expect(returned_ids).to include(recent_point.id)
        expect(returned_ids).to include(old_point.id)
      end
    end
  end

  describe 'GET /index (archived param is ignored)' do
    context 'when user is on lite plan and passes archived=true' do
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

      it 'ignores archived param and returns only recent points' do
        get api_v1_points_url(api_key: lite_user.api_key, archived: 'true')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        returned_ids = json_response.map { |p| p['id'] }

        expect(returned_ids).to include(recent_point.id)
        expect(returned_ids).not_to include(old_point.id)
      end
    end
  end

  describe 'POST /reapply_anomaly_filter' do
    before { Rails.cache.delete("anomaly_backfill_pending:#{user.id}") }

    it 'enqueues the backfill job in reset mode for the current user' do
      expect do
        post "/api/v1/points/reapply_anomaly_filter?api_key=#{user.api_key}"
      end.to have_enqueued_job(Points::AnomalyBackfillUserJob).with(user.id, reset: true)

      expect(response).to have_http_status(:accepted)
    end

    it 'returns 409 when a backfill is already pending' do
      Rails.cache.write("anomaly_backfill_pending:#{user.id}", true, expires_in: 30.minutes)

      expect do
        post "/api/v1/points/reapply_anomaly_filter?api_key=#{user.api_key}"
      end.not_to have_enqueued_job(Points::AnomalyBackfillUserJob)

      expect(response).to have_http_status(:conflict)
    end

    it 'requires authentication' do
      post '/api/v1/points/reapply_anomaly_filter'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'privacy zone masking' do
    let(:pz_user) { create(:user) }

    before do
      tag = create(:tag, :privacy_zone, user: pz_user, privacy_radius_meters: 1000)
      place = create(:place, user: pz_user, latitude: 52.444, longitude: 13.500)
      create(:tagging, tag: tag, taggable: place)
      create(:point, user: pz_user, lonlat: 'POINT(13.500 52.444)', timestamp: 1.hour.ago.to_i)
      create(:point, user: pz_user, lonlat: 'POINT(13.700 52.600)', timestamp: 30.minutes.ago.to_i)
    end

    it 'omits in-zone points when mask_privacy_zones=true' do
      get api_v1_points_url(api_key: pz_user.api_key, mask_privacy_zones: 'true', per_page: 100)

      coords = JSON.parse(response.body).map { |p| [p['longitude'].to_f, p['latitude'].to_f] }
      expect(coords).to include([13.700, 52.600])
      expect(coords).not_to include([13.500, 52.444])
    end

    it 'returns all points without the flag' do
      get api_v1_points_url(api_key: pz_user.api_key, per_page: 100)

      coords = JSON.parse(response.body).map { |p| [p['longitude'].to_f, p['latitude'].to_f] }
      expect(coords).to include([13.700, 52.600], [13.500, 52.444])
    end
  end

  describe 'GET /index bbox validation' do
    it 'rejects an inverted bbox with 400' do
      get "/api/v1/points?api_key=#{user.api_key}&" \
          'min_longitude=10&max_longitude=5&min_latitude=10&max_latitude=20'

      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects out-of-range latitude with 400' do
      get "/api/v1/points?api_key=#{user.api_key}&" \
          'min_longitude=-10&max_longitude=10&min_latitude=-100&max_latitude=10'

      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects non-numeric bbox values with 400' do
      get "/api/v1/points?api_key=#{user.api_key}&" \
          'min_longitude=foo&max_longitude=10&min_latitude=0&max_latitude=10'

      expect(response).to have_http_status(:bad_request)
    end
  end
end
