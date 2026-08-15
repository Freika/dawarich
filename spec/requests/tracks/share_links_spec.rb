# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tracks::ShareLinks', type: :request do
  let(:user) { create(:user) }
  let(:track) { create(:track, user: user, dominant_mode: :driving, distance: 42_000) }

  before { sign_in user }

  describe 'GET /tracks/:track_id/share_link/new' do
    it 'renders the modal frame' do
      get new_track_share_link_path(track)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('share-link-modal')
    end
  end

  describe 'POST /tracks/:track_id/share_link' do
    it 'creates a :track SharedLink for the track' do
      expect do
        post track_share_link_path(track), params: { shared_link: { magic_phrase: '' } }
      end.to change { user.shared_links.count }.by(1)
      link = user.shared_links.last
      expect(link.resource_type).to eq('track')
      expect(link.resource_id).to eq(track.id)
    end

    it 'auto-revokes any existing active share for this track (one-active rule)' do
      existing = create(:shared_link, user: user, resource_type: :track, resource_id: track.id)
      post track_share_link_path(track), params: { shared_link: { magic_phrase: 'new-link-here' } }
      expect(existing.reload.revoked_at).to be_present
      expect(track.shared_links.active.count).to eq(1)
    end

    it "returns 404 when sharing another user's track" do
      other_track = create(:track, user: create(:user))
      post track_share_link_path(other_track), params: { shared_link: {} }
      expect(response).to have_http_status(:not_found)
    end

    it 'derives a non-blank label naming the mode and distance when no name is given' do
      post track_share_link_path(track), params: { shared_link: { name: '' } }
      name = user.shared_links.last.name
      expect(name).to be_present
      expect(name).to include('Driving')
    end

    it 'falls back to a generic label for a track with no dominant_mode' do
      modeless = create(:track, user: user, dominant_mode: :unknown, distance: 0)
      post track_share_link_path(modeless), params: { shared_link: { name: '' } }
      expect(user.shared_links.last.name).to be_present
    end
  end

  describe 'PATCH /tracks/:track_id/share_link/revoke' do
    it 'sets revoked_at on the active share' do
      share = create(:shared_link, user: user, resource_type: :track, resource_id: track.id)
      patch revoke_track_share_link_path(track)
      expect(share.reload.revoked_at).to be_present
    end
  end

  describe 'POST /tracks/:track_id/share_link/regenerate' do
    it 'rotates the id (destroys old, creates new)' do
      share = create(:shared_link, user: user, resource_type: :track, resource_id: track.id)
      old_id = share.id
      post regenerate_track_share_link_path(track)
      expect(SharedLink.exists?(old_id)).to be false
      expect(track.shared_links.active.count).to eq(1)
    end
  end

  describe 'POST /tracks/:track_id/share_link/regenerate_phrase' do
    it 'changes the magic_phrase to a fresh generated value' do
      share = create(:shared_link, user: user, resource_type: :track, resource_id: track.id,
                                   magic_phrase: 'old-phrase-here')
      post regenerate_phrase_track_share_link_path(track)
      expect(share.reload.magic_phrase).not_to eq('old-phrase-here')
    end
  end

  describe 'DELETE /tracks/:track_id/share_link' do
    it 'deletes the active share' do
      share = create(:shared_link, user: user, resource_type: :track, resource_id: track.id)
      delete track_share_link_path(track)
      expect(SharedLink.exists?(share.id)).to be false
    end
  end
end
