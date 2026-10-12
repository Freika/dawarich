# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ShareLinks::Lives', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /share_links/live/new' do
    it 'renders the modal frame' do
      get new_share_links_live_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('share-link-modal')
    end
  end

  describe 'POST /share_links/live' do
    it 'creates a :live SharedLink with a nil resource_id' do
      expect do
        post share_links_live_path, params: { shared_link: { magic_phrase: '' } }
      end.to change { user.shared_links.where(resource_type: :live).count }.by(1)
      link = user.shared_links.last
      expect(link.resource_type).to eq('live')
      expect(link.resource_id).to be_nil
    end

    it 'auto-revokes any prior active live share (one-active rule)' do
      existing = create(:shared_link, :live, user: user)
      post share_links_live_path, params: { shared_link: { magic_phrase: 'new-link-here' } }
      expect(existing.reload.revoked_at).to be_present
      expect(user.shared_links.where(resource_type: :live).active.count).to eq(1)
    end

    it 'broadcasts a terminal {revoked: true} to the prior live share before revoking it' do
      existing = create(:shared_link, :live, user: user)
      expect do
        post share_links_live_path, params: { shared_link: { magic_phrase: '' } }
      end.to have_broadcasted_to(existing).from_channel(SharedLocationChannel).with(revoked: true)
    end

    it 'stores show_route when the route box is checked' do
      post share_links_live_path, params: { shared_link: { magic_phrase: '', settings: { show_route: '1' } } }
      expect(user.shared_links.last.settings['show_route']).to be(true)
    end

    it 'defaults show_route to false when the box is unchecked' do
      post share_links_live_path, params: { shared_link: { magic_phrase: '' } }
      expect(user.shared_links.last.settings['show_route']).to be(false)
    end
  end

  describe 'PATCH /share_links/live/revoke' do
    it 'revokes the active live share' do
      share = create(:shared_link, :live, user: user)
      patch revoke_share_links_live_path
      expect(share.reload.revoked_at).to be_present
    end

    it 'broadcasts a terminal {revoked: true} to the share stream' do
      share = create(:shared_link, :live, user: user)
      expect do
        patch revoke_share_links_live_path
      end.to have_broadcasted_to(share).from_channel(SharedLocationChannel).with(revoked: true)
    end
  end

  describe 'POST /share_links/live/regenerate' do
    it 'produces a valid nil-resource_id live record' do
      share = create(:shared_link, :live, user: user)
      old_id = share.id
      post regenerate_share_links_live_path
      expect(SharedLink.exists?(old_id)).to be false
      new_share = user.shared_links.where(resource_type: :live).active.first
      expect(new_share).to be_present
      expect(new_share.resource_id).to be_nil
    end

    it 'broadcasts a terminal {revoked: true} to the old share stream so open viewers disconnect' do
      share = create(:shared_link, :live, user: user)
      expect do
        post regenerate_share_links_live_path
      end.to have_broadcasted_to(share).from_channel(SharedLocationChannel).with(revoked: true)
    end
  end

  describe 'POST /share_links/live/regenerate_phrase' do
    it 'changes the magic phrase to a fresh generated value' do
      share = create(:shared_link, :live, user: user, magic_phrase: 'old-phrase-here')
      post regenerate_phrase_share_links_live_path
      expect(share.reload.magic_phrase).not_to eq('old-phrase-here')
    end

    it 'broadcasts {revoked: true} so viewers with the old phrase are cut off' do
      share = create(:shared_link, :live, user: user, magic_phrase: 'old-phrase-here')
      expect do
        post regenerate_phrase_share_links_live_path
      end.to have_broadcasted_to(share).from_channel(SharedLocationChannel).with(revoked: true)
    end
  end

  describe 'DELETE /share_links/live' do
    it 'deletes the active live share' do
      share = create(:shared_link, :live, user: user)
      delete share_links_live_path
      expect(SharedLink.exists?(share.id)).to be false
    end
  end

  describe 'SharedLink::DEFAULT_SETTINGS[:live]' do
    it 'no longer carries the vestigial history_hours key' do
      expect(SharedLink::DEFAULT_SETTINGS[:live]).not_to have_key('history_hours')
    end
  end
end
