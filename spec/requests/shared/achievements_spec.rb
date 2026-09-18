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

      expect(response.body).to include('property="og:title"')
      expect(response.body).to include('Germany Explorer')
      expect(response.body).to include('property="og:description"')
      expect(response.body).to include('<title>Germany Explorer — Dawarich</title>')
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
