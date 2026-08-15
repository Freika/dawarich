# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ShareLinks::Timelines', type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  describe 'GET /share_links/timeline/new' do
    it 'renders the modal frame' do
      get new_share_links_timeline_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('share-link-modal')
    end

    it 'pre-fills dates from query params when provided' do
      get new_share_links_timeline_path, params: { start_date: '2026-04-01', end_date: '2026-04-14' }
      expect(response.body).to include('2026-04-01')
      expect(response.body).to include('2026-04-14')
    end
  end

  describe 'POST /share_links/timeline' do
    it 'creates a timeline SharedLink' do
      expect do
        post share_links_timeline_path, params: {
          shared_link: { start_date: '2026-04-01', end_date: '2026-04-14', magic_phrase: '' }
        }
      end.to change { user.shared_links.where(resource_type: :timeline).count }.by(1)
      link = user.shared_links.where(resource_type: :timeline).last
      expect(link.settings['start_date']).to eq('2026-04-01')
      expect(link.settings['end_date']).to eq('2026-04-14')
      expect(link.resource_id).to be_nil
    end

    it 'auto-revokes any existing active timeline share for this user' do
      existing = create(:shared_link, user: user, resource_type: :timeline, resource_id: nil,
                                       settings: { 'start_date' => '2026-03-01', 'end_date' => '2026-03-14' },
                                       autobuild_trip: false)
      post share_links_timeline_path, params: {
        shared_link: { start_date: '2026-04-01', end_date: '2026-04-14' }
      }
      expect(existing.reload.revoked_at).to be_present
      expect(user.shared_links.where(resource_type: :timeline).active.count).to eq(1)
    end

    it 'rejects invalid date ranges' do
      post share_links_timeline_path, params: {
        shared_link: { start_date: '2026-04-14', end_date: '2026-04-01' }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'PATCH /share_links/timeline/revoke' do
    it 'sets revoked_at on the active timeline share' do
      share = create(:shared_link, user: user, resource_type: :timeline, resource_id: nil,
                                    settings: { 'start_date' => '2026-04-01', 'end_date' => '2026-04-14' },
                                    autobuild_trip: false)
      patch revoke_share_links_timeline_path
      expect(share.reload.revoked_at).to be_present
    end
  end

  describe 'POST /share_links/timeline/regenerate' do
    it 'rotates the id and queues an OG image render for the new link' do
      share = create(:shared_link, user: user, resource_type: :timeline, resource_id: nil,
                                    settings: { 'start_date' => '2026-04-01', 'end_date' => '2026-04-14' },
                                    autobuild_trip: false)
      old_id = share.id
      post regenerate_share_links_timeline_path
      expect(SharedLink.exists?(old_id)).to be false
      expect(user.shared_links.where(resource_type: :timeline).active.count).to eq(1)
    end
  end

  describe 'POST /share_links/timeline/regenerate_phrase' do
    it 'changes the magic_phrase' do
      share = create(:shared_link, user: user, resource_type: :timeline, resource_id: nil,
                                    magic_phrase: 'old-phrase-here',
                                    settings: { 'start_date' => '2026-04-01', 'end_date' => '2026-04-14' },
                                    autobuild_trip: false)
      post regenerate_phrase_share_links_timeline_path
      expect(share.reload.magic_phrase).not_to eq('old-phrase-here')
      expect(share.magic_phrase).to match(/\A[a-z]+-[a-z]+-[a-z]+\z/)
    end
  end

  describe 'DELETE /share_links/timeline' do
    it 'deletes the active timeline share' do
      share = create(:shared_link, user: user, resource_type: :timeline, resource_id: nil,
                                    settings: { 'start_date' => '2026-04-01', 'end_date' => '2026-04-14' },
                                    autobuild_trip: false)
      delete share_links_timeline_path
      expect(SharedLink.exists?(share.id)).to be false
    end
  end
end
