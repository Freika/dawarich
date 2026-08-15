# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ShareLinks::Hubs', type: :request do
  let(:user) { create(:user) }

  def timeline_share
    create(:shared_link, user: user, resource_type: :timeline, resource_id: nil,
                         settings: { 'start_date' => '2026-04-01', 'end_date' => '2026-04-14' },
                         autobuild_trip: false)
  end

  context 'when signed out' do
    it 'redirects to login' do
      get share_links_hub_path
      expect(response).to have_http_status(:redirect)
    end
  end

  context 'when signed in' do
    before { sign_in user }

    it 'renders the modal frame with both core tabs' do
      get share_links_hub_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="share-link-modal"')
      expect(response.body).to include('data-testid="hub-tab-live"')
      expect(response.body).to include('data-testid="hub-tab-timeline"')
    end

    it 'shows the live create form (with route checkbox) when no live share exists' do
      get share_links_hub_path
      expect(response.body).to include('Share the route')
    end

    it 'shows the live active state when a live share exists' do
      live = create(:shared_link, :live, user: user)
      get share_links_hub_path
      expect(response.body).to include(public_shared_link_url(live.id))
    end

    it 'defaults the timeline form dates to the requested range' do
      get share_links_hub_path(start_date: '2026-03-02', end_date: '2026-03-09')
      expect(response.body).to include('2026-03-02')
      expect(response.body).to include('2026-03-09')
    end

    it 'hides the Shared tab when the user has no active shares' do
      get share_links_hub_path
      expect(response.body).not_to include('data-testid="hub-tab-shared"')
    end

    it 'shows the Shared tab listing active shares when any exist' do
      tl = timeline_share
      get share_links_hub_path
      expect(response.body).to include('data-testid="hub-tab-shared"')
      expect(response.body).to include(public_shared_link_url(tl.id))
    end
  end

  describe 'hub turbo stream responses' do
    before { sign_in user }

    let(:dates) { { hub: 1, start_date: '2026-06-01', end_date: '2026-06-20' } }

    it 'creating a live share via the hub streams both the modal and indicator (with dot)' do
      post share_links_live_path(dates), params: { shared_link: { magic_phrase: '' } }
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('target="share-hub-body"')
      expect(response.body).to include('target="live-share-indicator"')
      expect(response.body).to include('data-testid="live-share-dot"')
    end

    it 'revoking the live share via the hub clears the indicator dot' do
      create(:shared_link, :live, user: user)
      patch revoke_share_links_live_path(dates)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('target="live-share-indicator"')
      expect(response.body).not_to include('data-testid="live-share-dot"')
    end

    it 'regenerate via the hub responds with turbo streams' do
      create(:shared_link, :live, user: user)
      post regenerate_share_links_live_path(dates)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('target="share-hub-body"')
    end

    it 'regenerate_phrase via the hub responds with turbo streams' do
      create(:shared_link, :live, :with_phrase, user: user)
      post regenerate_phrase_share_links_live_path(dates)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end

    it 'an invalid hub create re-renders the hub modal with errors (422)' do
      post share_links_live_path(dates), params: { shared_link: { magic_phrase: 'a' * 256 } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('alert-error')
      expect(response.body).to include('data-testid="hub-tab-live"')
    end

    it 'shows a timeline create validation error exactly once (no duplicate banner)' do
      post share_links_timeline_path(dates),
           params: { shared_link: { magic_phrase: 'a' * 256, start_date: '2026-06-01', end_date: '2026-06-20' } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.scan('alert-error').size).to eq(1)
    end

    it 'generic revoke via the hub responds with turbo streams' do
      share = create(:shared_link, :live, user: user)
      patch revoke_share_links_share_path(share, dates)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('target="live-share-indicator"')
    end

    it 'a non-hub live create still redirects (regression)' do
      post share_links_live_path, params: { shared_link: { magic_phrase: '' } }
      expect(response).to have_http_status(:redirect)
    end
  end
end
