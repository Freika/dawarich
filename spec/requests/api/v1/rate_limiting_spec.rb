# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API Rate Limiting', type: :request do
  let(:original_limits) { Rack::Attack.api_rate_limits.dup }

  before do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  after do
    Rack::Attack.api_rate_limits = original_limits
  end

  describe 'rate limit headers' do
    context 'when user is on lite plan' do
      let!(:user) do
        u = create(:user)
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

    context 'when on a self-hosted instance' do
      let!(:user) { create(:user) }

      it 'does not include rate limit headers' do
        get api_v1_points_url(api_key: user.api_key)

        expect(response.headers['X-RateLimit-Limit']).to be_nil
      end
    end
  end

  describe 'throttling' do
    context 'when lite user exceeds rate limit' do
      let!(:user) do
        u = create(:user)
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

      it 'is not rate limited' do
        get api_v1_points_url(api_key: user.api_key)

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
