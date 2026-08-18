# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API Rate Limiting', type: :request do
  let(:original_limits) { Rack::Attack.api_rate_limits.dup }

  before do
    # Rack::Attack is globally disabled in test env so unrelated request
    # specs don't share throttle counters; re-enable for this file since
    # it explicitly exercises the throttling behavior.
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  after do
    Rack::Attack.api_rate_limits = original_limits
    Rack::Attack.enabled = false
  end

  describe 'rate limit headers' do
    context 'when user is on lite plan' do
      let!(:user) do
        u = create(:user)
        # update_columns bypasses the activate callback that resets plan to :pro
        u.update_columns(plan: User.plans[:lite])
        u
      end

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'includes rate limit headers with a limit of 200' do
        get api_v1_points_url(api_key: user.api_key)

        expect(response.headers['X-RateLimit-Limit']).to eq('200')
        expect(response.headers['X-RateLimit-Remaining']).to be_present
        expect(response.headers['X-RateLimit-Reset']).to be_present
      end
    end

    context 'when user is on pro plan' do
      let!(:user) do
        u = create(:user)
        # update_columns bypasses the activate callback that resets plan to :pro
        u.update_columns(plan: User.plans[:pro])
        u
      end

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'includes rate limit headers with a limit of 1000' do
        get api_v1_points_url(api_key: user.api_key)

        expect(response.headers['X-RateLimit-Limit']).to eq('1000')
        expect(response.headers['X-RateLimit-Remaining']).to be_present
        expect(response.headers['X-RateLimit-Reset']).to be_present
      end
    end

    context 'when user is on family plan' do
      let!(:user) do
        u = create(:user)
        u.update_columns(plan: User.plans[:family])
        u
      end

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'includes rate limit headers with a limit of 1000' do
        get api_v1_points_url(api_key: user.api_key)

        expect(response.headers['X-RateLimit-Limit']).to eq('1000')
      end
    end

    context 'when user is a lite member of a family-plan family' do
      let!(:owner) do
        u = create(:user)
        u.update_columns(plan: User.plans[:family])
        u
      end
      let!(:family) { create(:family, creator: owner) }
      let!(:member) do
        u = create(:user)
        u.update_columns(plan: User.plans[:lite])
        u
      end

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        create(:family_membership, :owner, family: family, user: owner)
        create(:family_membership, family: family, user: member)
      end

      it 'gets the full 1000 limit via effective plan' do
        get api_v1_points_url(api_key: member.api_key)

        expect(response.headers['X-RateLimit-Limit']).to eq('1000')
      end
    end

    context 'when on a self-hosted instance' do
      let!(:user) { create(:user) }

      it 'does not include rate limit headers' do
        get api_v1_points_url(api_key: user.api_key)

        expect(response.headers['X-RateLimit-Limit']).to be_nil
      end
    end
  end

  describe 'tile requests' do
    let!(:user) do
      u = create(:user)
      # update_columns bypasses the activate callback that resets plan to :pro
      u.update_columns(plan: User.plans[:lite])
      u
    end
    let(:tile_path) { '/api/v1/tiles/points/0/0/0.mvt' }
    let(:original_tiles_limit) { Rack::Attack.tiles_limit }
    let(:original_tiles_burst_limit) { Rack::Attack.tiles_burst_limit }

    before do
      original_tiles_limit
      original_tiles_burst_limit
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    after do
      Rack::Attack.tiles_limit = original_tiles_limit
      Rack::Attack.tiles_burst_limit = original_tiles_burst_limit
    end

    it 'does not count tile requests toward the general api quota' do
      Rack::Attack.api_rate_limits = { 'lite' => 2, 'pro' => 2 }

      3.times { get tile_path, params: { api_key: user.api_key } }
      get api_v1_points_url(api_key: user.api_key)

      expect(response).not_to have_http_status(:too_many_requests)
    end

    it 'throttles tiles on their own limit' do
      Rack::Attack.tiles_limit = 3

      4.times { get tile_path, params: { api_key: user.api_key } }

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'throttles sustained tile bursts on the short window' do
      Rack::Attack.tiles_burst_limit = 3

      4.times { get tile_path, params: { api_key: user.api_key } }

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'covers tracks and anomalies tiles with the same throttle key as points' do
      Rack::Attack.tiles_limit = 5

      2.times { get '/api/v1/tiles/points/0/0/0.mvt', params: { api_key: user.api_key } }
      2.times { get '/api/v1/tiles/tracks/0/0/0.mvt', params: { api_key: user.api_key } }
      2.times { get '/api/v1/tiles/anomalies/0/0/0.mvt', params: { api_key: user.api_key } }

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'keeps a realistic three-source pan sequence under the shipped burst budget' do
      # ~30 tiles/source/pan × 3 sources × 3 rapid pans = 270 requests in one
      # burst window — must fit the raised (900) budget with headroom.
      sources = %w[points tracks anomalies]
      270.times do |i|
        get "/api/v1/tiles/#{sources[i % 3]}/0/0/0.mvt", params: { api_key: user.api_key }
      end

      expect(response).not_to have_http_status(:too_many_requests)
    end

    it 'keys the tile throttle off the Bearer header when no api_key param is present' do
      Rack::Attack.tiles_limit = 3

      4.times { get tile_path, headers: { 'Authorization' => "Bearer #{user.api_key}" } }

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'does not throttle tiles on self-hosted instances' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      Rack::Attack.tiles_limit = 2

      5.times { get tile_path, params: { api_key: user.api_key } }

      expect(response).not_to have_http_status(:too_many_requests)
    end
  end

  describe 'throttling' do
    context 'when lite user exceeds rate limit' do
      let!(:user) do
        u = create(:user)
        # update_columns bypasses the activate callback that resets plan to :pro
        u.update_columns(plan: User.plans[:lite])
        u
      end

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        Rack::Attack.api_rate_limits = { 'lite' => 3, 'pro' => 5 }
      end

      it 'returns 429 with Retry-After header after exceeding limit' do
        4.times { get api_v1_points_url(api_key: user.api_key) }

        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers['Retry-After']).to be_present
      end

      it 'returns a JSON error body' do
        4.times { get api_v1_points_url(api_key: user.api_key) }

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('rate_limit_exceeded')
        expect(json_response['upgrade_url']).to be_present
      end
    end

    context 'when pro user exceeds rate limit' do
      let!(:user) do
        u = create(:user)
        # update_columns bypasses the activate callback that resets plan to :pro
        u.update_columns(plan: User.plans[:pro])
        u
      end

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        Rack::Attack.api_rate_limits = { 'lite' => 3, 'pro' => 5 }
      end

      it 'returns 429 after exceeding limit' do
        6.times { get api_v1_points_url(api_key: user.api_key) }

        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers['Retry-After']).to be_present
      end
    end

    context 'when on a self-hosted instance' do
      let!(:user) { create(:user) }

      it 'is not rate limited even after many requests' do
        Rack::Attack.api_rate_limits = { 'lite' => 2, 'pro' => 2 }
        5.times { get api_v1_points_url(api_key: user.api_key) }

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'trial welcome throttle' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'throttles GET /trial/welcome at 30/min/IP' do
      30.times do
        get '/trial/welcome?token=x'
        expect(response).not_to have_http_status(:too_many_requests)
      end

      get '/trial/welcome?token=x'
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'signup throttle' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'throttles POST /users at 5/min/IP' do
      5.times do
        post '/users', params: { user: { email: "burst-#{SecureRandom.hex(3)}@example.com", password: 'x' } }
        expect(response).not_to have_http_status(:too_many_requests)
      end

      post '/users', params: { user: { email: 'burst-final@example.com', password: 'x' } }
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'throttles POST /users at 20/hour/IP independently of the per-minute throttle' do
      21.times do
        post '/users', params: { user: { email: "hourly-#{SecureRandom.hex(3)}@example.com", password: 'x' } }
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
