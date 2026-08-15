# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared link rate limiting', type: :request do
  let(:link) { create(:shared_link, :with_phrase) }

  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
  end

  after do
    Rack::Attack.enabled = false
    Rack::Attack.cache.store.clear
  end

  it 'throttles unlock attempts after 5 in 5 minutes (even on self-hosted)' do
    5.times do |i|
      post "/s/#{link.id}/unlock", params: { phrase: "wrong-#{i}" }, env: { 'REMOTE_ADDR' => '203.0.113.1' }
      expect(response.status).to eq(401)
    end
    post "/s/#{link.id}/unlock", params: { phrase: 'wrong-final' }, env: { 'REMOTE_ADDR' => '203.0.113.1' }
    expect(response).to have_http_status(:too_many_requests)
  end

  describe 'viewer throttle' do
    let(:original_viewer_limit) { Rack::Attack.shared_links_viewer_limit }

    before { Rack::Attack.shared_links_viewer_limit = 2 }
    after  { Rack::Attack.shared_links_viewer_limit = original_viewer_limit }

    it 'throttles viewer + shared API requests past the limit on cloud' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      3.times { get "/s/#{link.id}", env: { 'REMOTE_ADDR' => '203.0.113.2' } }
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'never throttles public pages on self-hosted' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      5.times { get "/s/#{link.id}", env: { 'REMOTE_ADDR' => '203.0.113.3' } }
      expect(response).not_to have_http_status(:too_many_requests)
    end
  end
end
