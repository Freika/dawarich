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

  describe 'sharing a filtered import' do
    let!(:selected_import) { create(:import, user: user) }
    let!(:other_import) { create(:import, user: user) }
    let(:dates) { { start_date: '2026-04-01', end_date: '2026-04-14' } }

    it 'carries the import from the hub into the creation form' do
      get share_links_hub_path, params: dates.merge(import_id: selected_import.id, tab: 'timeline')
      field = Nokogiri::HTML(response.body).at_css('input[name="shared_link[import_id]"]')
      expect(field&.[]('value')).to eq(selected_import.id.to_s)
      expect(response.body).to include(selected_import.name)
    end

    it 'exposes only the selected import to an anonymous viewer' do
      selected = create(:point, user: user, import: selected_import, timestamp: Time.utc(2026, 4, 5).to_i)
      create(:point, user: user, import: other_import, timestamp: Time.utc(2026, 4, 5, 1).to_i)
      create(:point, user: user, timestamp: Time.utc(2026, 4, 5, 2).to_i)
      post share_links_timeline_path, params: { shared_link: dates.merge(import_id: selected_import.id) }
      link = user.shared_links.timeline.active.sole
      sign_out user

      get "/api/v1/shared/#{link.id}/points"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map(&:last)).to eq([selected.timestamp])
    end

    it "rejects another user's import without revoking an existing link" do
      existing = create(:shared_link, user: user, resource_type: :timeline, resource_id: nil,
                                      settings: dates.stringify_keys, autobuild_trip: false)
      foreign_import = create(:import)
      post share_links_timeline_path, params: { shared_link: dates.merge(import_id: foreign_import.id) }
      expect(response).to have_http_status(:unprocessable_content)
      expect(existing.reload).to be_active
      expect(user.shared_links.timeline.active.count).to eq(1)
    end

    it 'keeps the import scope after a validation error in the hub' do
      post share_links_timeline_path(hub: 1), params: {
        shared_link: dates.merge(import_id: selected_import.id, end_date: 'invalid')
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('name="shared_link[import_id]"', "value=\"#{selected_import.id}\"")
    end

    it 'opens a filtered form even when an unfiltered link already exists' do
      create(:shared_link, user: user, resource_type: :timeline, resource_id: nil,
                           settings: dates.stringify_keys, autobuild_trip: false)
      get new_share_links_timeline_path, params: dates.merge(import_id: selected_import.id)
      expect(response.body).to include('name="shared_link[import_id]"')
    end

    it 'keeps the filter when the URL is regenerated' do
      post share_links_timeline_path, params: { shared_link: dates.merge(import_id: selected_import.id) }
      original = user.shared_links.timeline.active.sole
      post regenerate_share_links_timeline_path
      replacement = user.shared_links.timeline.active.sole
      expect(replacement.id).not_to eq(original.id)
      expect(replacement.settings['import_id']).to eq(selected_import.id.to_s)
    end

    it 'rejects malformed import identifiers' do
      post share_links_timeline_path, params: { shared_link: dates.merge(import_id: "#{selected_import.id}garbage") }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.shared_links.timeline.active).to be_empty
    end

    it 'applies privacy zones within the selected import' do
      home = create(:place, user: user, latitude: 52.52, longitude: 13.4)
      tag = create(:tag, user: user, privacy_radius_meters: 500)
      create(:tagging, tag: tag, taggable: home)
      create(:point, user: user, import: selected_import, latitude: 52.52, longitude: 13.4,
                     timestamp: Time.utc(2026, 4, 5).to_i)
      visible = create(:point, user: user, import: selected_import, latitude: 53.0, longitude: 14.0,
                              timestamp: Time.utc(2026, 4, 5, 1).to_i)
      post share_links_timeline_path, params: { shared_link: dates.merge(import_id: selected_import.id) }
      link = user.shared_links.timeline.active.sole
      sign_out user
      get "/api/v1/shared/#{link.id}/points"
      expect(response.parsed_body.map(&:last)).to eq([visible.timestamp])
    end

    it 'does not serve external photos or thumbnails for an import-scoped share' do
      link = create(:shared_link, user: user, resource_type: :timeline, resource_id: nil,
                                 settings: dates.stringify_keys.merge(
                                   'import_id' => selected_import.id, 'show_photos' => true
                                 ),
                                 autobuild_trip: false)
      external_photo = { id: 'other-source-photo', source: 'immich', latitude: 53.0, longitude: 14.0,
                         capturedAt: '2026-04-05T12:00:00Z' }
      allow(Photos::Search).to receive(:cached).and_return([external_photo])
      sign_out user
      get "/api/v1/shared/#{link.id}/photos"
      expect(response.parsed_body).to eq([])
      get "/api/v1/shared/#{link.id}/photos/asset/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:not_found)
    end

    it 'does not broaden a link when its import is deleted' do
      link = create(:shared_link, user: user, resource_type: :timeline, resource_id: nil,
                                 settings: dates.stringify_keys.merge('import_id' => selected_import.id),
                                 autobuild_trip: false)
      selected_import.destroy!
      create(:point, user: user, import: other_import, timestamp: Time.utc(2026, 4, 5).to_i)
      sign_out user
      get "/api/v1/shared/#{link.id}/points"
      expect(response.parsed_body).to eq([])
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
