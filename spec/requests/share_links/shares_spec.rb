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
end
