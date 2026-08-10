# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trips::ShareLinks', type: :request do
  let(:user) { create(:user) }
  let(:trip) { create(:trip, user: user) }

  before { sign_in user }

  describe 'GET /trips/:trip_id/share_link/new' do
    it 'renders the modal frame' do
      get new_trip_share_link_path(trip)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('share-link-modal')
    end
  end

  describe 'POST /trips/:trip_id/share_link' do
    it 'creates a SharedLink for the trip' do
      expect do
        post trip_share_link_path(trip), params: { shared_link: { magic_phrase: '' } }
      end.to change { user.shared_links.count }.by(1)
      link = user.shared_links.last
      expect(link.resource_type).to eq('trip')
      expect(link.resource_id).to eq(trip.id)
    end

    it 'auto-revokes any existing active share for this trip (one-active rule)' do
      existing = create(:shared_link, user: user, resource_type: :trip, resource_id: trip.id)
      post trip_share_link_path(trip), params: { shared_link: { magic_phrase: 'new-link-here' } }
      expect(existing.reload.revoked_at).to be_present
      expect(trip.shared_links.active.count).to eq(1)
    end

    it "returns 404 when sharing another user's trip" do
      other_trip = create(:trip, user: create(:user))
      post trip_share_link_path(other_trip), params: { shared_link: {} }
      expect(response).to have_http_status(:not_found)
    end

    it 'auto-fills a default name from the trip when none is given' do
      post trip_share_link_path(trip), params: { shared_link: { name: '' } }
      expect(user.shared_links.last.name).to include(trip.name)
    end

    it 'stores a start-of-day expiry from the form date' do
      user.update!(settings: user.settings.to_h.merge('timezone' => 'Europe/Berlin'))
      zone = Time.find_zone!('Europe/Berlin')
      date = zone.today + 2

      post trip_share_link_path(trip), params: { shared_link: { expires_at: date.iso8601 } }

      expect(user.shared_links.last.expires_at).to eq(zone.local(date.year, date.month, date.day))
    end

    it 'keeps the existing share when the new one fails validation' do
      existing = create(:shared_link, user: user, resource_type: :trip, resource_id: trip.id)
      expect do
        post trip_share_link_path(trip), params: { shared_link: { expires_at: '2020-01-01' } }
      end.not_to(change { user.shared_links.active.count })
      expect(existing.reload.revoked_at).to be_nil
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'PATCH /trips/:trip_id/share_link/revoke' do
    it 'sets revoked_at on the active share' do
      share = create(:shared_link, user: user, resource_type: :trip, resource_id: trip.id)
      patch revoke_trip_share_link_path(trip)
      expect(share.reload.revoked_at).to be_present
    end

    it 'redirects with an alert when no active share exists' do
      patch revoke_trip_share_link_path(trip)
      expect(response).to redirect_to(trip_path(trip))
      follow_redirect!
      expect(response.body).to include('No active share link')
    end
  end

  describe 'POST /trips/:trip_id/share_link/regenerate_phrase' do
    it 'changes the magic_phrase to a fresh generated value' do
      share = create(:shared_link, user: user, resource_type: :trip, resource_id: trip.id,
                                   magic_phrase: 'old-phrase-here')
      post regenerate_phrase_trip_share_link_path(trip)
      expect(share.reload.magic_phrase).not_to eq('old-phrase-here')
      expect(share.magic_phrase).to match(/\A[a-z]+-[a-z]+-[a-z]+\z/)
    end
  end

  describe 'POST /trips/:trip_id/share_link/regenerate' do
    it 'rotates the id (destroys old, creates new)' do
      share = create(:shared_link, user: user, resource_type: :trip, resource_id: trip.id)
      old_id = share.id
      post regenerate_trip_share_link_path(trip)
      expect(SharedLink.exists?(old_id)).to be false
      expect(trip.shared_links.active.count).to eq(1)
    end
  end

  describe 'DELETE /trips/:trip_id/share_link' do
    it 'deletes the active share' do
      share = create(:shared_link, user: user, resource_type: :trip, resource_id: trip.id)
      delete trip_share_link_path(trip)
      expect(SharedLink.exists?(share.id)).to be false
    end
  end
end
