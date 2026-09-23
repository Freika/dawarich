# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared achievements' do
  describe 'GET /shared/achievements/:uuid' do
    before { Flipper.enable(:achievements) }

    after { Flipper.disable(:achievements) }

    let(:user) { create(:user) }
    let!(:exploration) do
      create(:achievement_progress, user: user, achievement_key: 'exploration',
                                    state: { 'earned' => { 'DE-BY' => '2026-07-01T10:00:00Z' } })
    end
    let(:progress) do
      create(
        :achievement_progress,
        user: user,
        achievement_key: 'country_de',
        sharing_enabled: true,
        sharing_uuid: SecureRandom.uuid
      )
    end

    it 'treats a link whose owner is being deleted as not found' do
      uuid = progress.sharing_uuid
      user.mark_as_deleted!

      get shared_achievement_path(uuid)

      expect(response).to redirect_to(root_path)
    end

    it 'renders the badge page without authentication' do
      get shared_achievement_path(progress.sharing_uuid)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Germany Explorer')
      expect(response.body).to include('1/16')
      expect(response.body).not_to include('Bavaria')
      expect(response.body).not_to include('1 Jul 2026')
    end

    it 'keeps an unexplored shared card grey and static' do
      exploration.update!(state: { 'earned' => {} })

      get shared_achievement_path(progress.sharing_uuid)

      card = Nokogiri::HTML(response.body).at_css('[data-achievement-card-locked-value="true"]')
      expect(card).to be_present
      expect(card['data-action']).not_to include('pointermove->achievement-card#move')
      expect(card.at_css('.ach-spectral--locked')).to be_present
    end

    it 'is embeddable in third-party iframes' do
      get shared_achievement_path(progress.sharing_uuid)

      expect(response.headers['X-Frame-Options']).to be_nil
      expect(response.headers['Content-Security-Policy']).to include('frame-ancestors *')
    end

    it 'offers a card-only embed document without shared-site chrome' do
      get shared_achievement_path(progress.sharing_uuid), params: { embed: 1 }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css('.ach-embed-page .ach-card')).to be_present
      expect(document.at_css('header')).to be_nil
      expect(document.at_css('footer')).to be_nil
    end

    it 'uses the public shared layout, not the app shell' do
      get shared_achievement_path(progress.sharing_uuid)

      expect(response.body).to include('Try Dawarich Cloud')
      expect(response.body).not_to include('data-controller="family-navbar-indicator"')
    end

    it 'carries social preview metadata' do
      get shared_achievement_path(progress.sharing_uuid)

      head = Nokogiri::HTML(response.body).at_css('head')
      expected_image_url = shared_achievement_image_url(progress.sharing_uuid)
      expect(head.at_css('meta[property="og:title"]')['content']).to include('Germany Explorer')
      expect(head.at_css('meta[property="og:description"]')).to be_present
      expect(head.at_css('meta[property="og:image"]')['content']).to eq(expected_image_url)
      expect(head.at_css('meta[property="og:image:type"]')['content']).to eq('image/png')
      expect(head.at_css('meta[property="og:image:width"]')['content']).to eq('1200')
      expect(head.at_css('meta[property="og:image:height"]')['content']).to eq('630')
      expect(head.at_css('meta[name="twitter:card"]')['content']).to eq('summary_large_image')
      expect(head.at_css('meta[name="twitter:image"]')['content']).to eq(expected_image_url)
      expect(response.body).to include('<title>Germany Explorer — Dawarich</title>')
    end

    it 'serves a PNG preview with the card contents' do
      get shared_achievement_image_path(progress.sharing_uuid)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('image/png')
      expect(response.body.b).to start_with("\x89PNG\r\n\x1A\n".b)
      expect(response.body.byteslice(16, 8).unpack('NN')).to eq([1200, 630])
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'does not serve a preview after sharing is disabled' do
      get shared_achievement_image_path(progress.sharing_uuid)
      expect(response).to have_http_status(:ok)

      progress.update!(sharing_enabled: false)

      get shared_achievement_image_path(progress.sharing_uuid)

      expect(response).to have_http_status(:not_found)
    end

    it 'does not serve a preview while achievements are disabled' do
      Flipper.disable(:achievements)

      get shared_achievement_image_path(progress.sharing_uuid)

      expect(response).to have_http_status(:not_found)
    end

    it 'refreshes a completed preview when the owner changes timezone' do
      earned = Achievements::Registry.find('country_de').region_codes.index_with { '2026-07-20T00:30:00Z' }
      exploration.update!(state: { 'earned' => earned })
      user.update!(settings: user.settings.merge('timezone' => 'UTC'))

      get shared_achievement_image_path(progress.sharing_uuid)
      utc_png = response.body

      user.update!(settings: user.settings.merge('timezone' => 'America/Los_Angeles'))
      get shared_achievement_image_path(progress.sharing_uuid)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to eq(utc_png)
    end

    it 'redirects when sharing is disabled' do
      progress.update!(sharing_enabled: false)

      get shared_achievement_path(progress.sharing_uuid)

      expect(response).to redirect_to(root_path)
    end

    it 'redirects for an unknown uuid' do
      get shared_achievement_path(SecureRandom.uuid)

      expect(response).to redirect_to(root_path)
    end

    it 'redirects while the feature is disabled' do
      Flipper.disable(:achievements)

      get shared_achievement_path(progress.sharing_uuid)

      expect(response).to redirect_to(root_path)
    end

    it 'describes continent progress in countries for social previews' do
      progress.update!(achievement_key: 'continent_europe')
      exploration.update!(state: { 'earned' => { 'DE' => '2026-07-01T10:00:00Z' } })

      get shared_achievement_path(progress.sharing_uuid)

      expect(response.body).to include('1/50 countries explored')
    end

    it 'renders public card copy in its owner locale' do
      user.persist_locale!(:de)

      get shared_achievement_path(progress.sharing_uuid)

      expect(response.body).to include('Germany-Entdecker')
      expect(response.body).to include('Selten')
      expect(response.body).to include('Aufgezeichnet mit')
    end
  end
end
