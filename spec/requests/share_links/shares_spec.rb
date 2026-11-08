# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ShareLinks::Shares', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'PATCH /share_links/shares/:id/revoke' do
    it 'revokes the user own share' do
      share = create(:shared_link, :live, user: user)
      patch revoke_share_links_share_path(share, hub: 1)
      expect(share.reload.revoked_at).to be_present
      expect(share.reload).not_to be_active
    end

    it 'revokes a track or trip share too' do
      trip = create(:trip, user: user)
      share = create(:shared_link, user: user, resource_type: :trip, resource_id: trip.id)
      patch revoke_share_links_share_path(share, hub: 1)
      expect(share.reload.revoked_at).to be_present
    end

    it 'broadcasts {revoked: true} when revoking a live share' do
      share = create(:shared_link, :live, user: user)
      expect do
        patch revoke_share_links_share_path(share, hub: 1)
      end.to have_broadcasted_to(share).from_channel(SharedLocationChannel).with(revoked: true)
    end

    it 'returns 404 for another users share and does not modify it' do
      other = create(:shared_link, :live, user: create(:user))
      patch revoke_share_links_share_path(other, hub: 1)
      expect(response).to have_http_status(:not_found)
      expect(other.reload.revoked_at).to be_nil
    end
  end

  describe 'editing the freshness window of a live share' do
    let(:share) { create(:shared_link, :live, user: user, settings: { 'live_freshness_seconds' => 3600 }) }

    it 'preselects the current window' do
      get edit_share_links_share_path(share)

      selected = Nokogiri::HTML(response.body)
                         .at_css('select[name="shared_link[settings][live_freshness_seconds]"] option[selected]')
      expect(selected['value']).to eq('3600')
    end

    it 'stores a new window as a number' do
      patch share_links_share_path(share), params: { shared_link: { settings: { live_freshness_seconds: '86400' } } }

      expect(share.reload.settings['live_freshness_seconds']).to eq(86_400)
    end

    it 'rejects a window outside the allowed list and keeps the old one' do
      patch share_links_share_path(share), params: { shared_link: { settings: { live_freshness_seconds: '604800' } } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(share.reload.settings['live_freshness_seconds']).to eq(3600)
    end

    it 'does not offer the window on a trip share' do
      trip_share = create(:shared_link, user: user, resource_type: :trip, resource_id: create(:trip, user: user).id)

      get edit_share_links_share_path(trip_share)

      expect(response.body).not_to include('live_freshness_seconds')
    end

    it 'ignores a window sent for a trip share' do
      trip_share = create(:shared_link, user: user, resource_type: :trip, resource_id: create(:trip, user: user).id)

      patch share_links_share_path(trip_share),
            params: { shared_link: { settings: { live_freshness_seconds: '3600' } } }

      expect(trip_share.reload.settings).not_to have_key('live_freshness_seconds')
    end
  end
end
