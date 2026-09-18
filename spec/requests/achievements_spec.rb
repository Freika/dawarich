# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Achievements' do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /achievements' do
    context 'when the feature flag is enabled' do
      before { Flipper.enable(:achievements) }
      after { Flipper.disable(:achievements) }

      def exploration(earned)
        create(:achievement_progress, user:, achievement_key: 'exploration', state: { 'earned' => earned })
      end

      it 'renders continents rather than every set' do
        exploration('DE-BY' => '2026-07-01T10:00:00Z', 'DE' => '2026-07-01T10:00:00Z')

        get achievements_path

        expect(response.body).to include('Europe Explorer')
        expect(response.body).not_to include('Border Hopper')
        expect(response.body).not_to include('Germany Explorer')
      end

      it 'counts distinct codes in the summary instead of summing sets' do
        exploration('DE' => '2026-07-01T10:00:00Z', 'FR' => '2026-07-02T10:00:00Z')

        get achievements_path

        expect(response.body).to include('ach-stats')
        expect(response.body).to include('<span class="ach-stat-total">/238</span>')
      end

      it 'explains how to start when the collection has no exploration data' do
        get achievements_path

        document = Nokogiri::HTML(response.body)
        expect(document.at_css('.ach-getting-started').text).to include('Record or import location data')
        expect(document.at_css('.ach-getting-started a')['href']).to eq(new_import_path)
        expect(document.css('.ach-grid .ach-spectral')).not_to be_empty
      end

      describe 'first-view celebration' do
        it 'celebrates a newly completed set exactly once' do
          all_earned = Achievements::Registry.find('country_de').region_codes.index_with { '2026-07-19' }
          progress = exploration(all_earned)

          get achievement_path('country_de')

          expect(response.body).to include('ach-card-wrap--celebrate')
          expect(progress.reload.state.dig('celebrated', 'country_de')).to be_present

          get achievement_path('country_de')

          expect(response.body).not_to include('ach-card-wrap--celebrate')
        end

        it 'does not mark hidden world tiers as celebrated' do
          progress = exploration(
            'DE' => '2026-07-01', 'FR' => '2026-07-02', 'IT' => '2026-07-03',
            'ES' => '2026-07-04', 'PT' => '2026-07-05'
          )

          get achievements_path

          expect(progress.reload.state.dig('celebrated', 'border_hopper')).to be_nil
        end
      end

      describe 'GET /achievements/:key' do
        it 'uses the application header and accessible collection navigation' do
          get achievement_path('continent_europe')

          document = Nokogiri::HTML(response.body)
          expect(document.at_css('h1').text).to eq('Europe Explorer')
          expect(document.at_css('nav[aria-label="Breadcrumb"]').text).to include('Achievements')
          expect(document.at_css('.ach-side--desktop [aria-current="page"]')['href'])
            .to eq(achievement_path('continent_europe'))
          expect(document.at_css('.ach-mobile-nav summary').text).to include('Europe')
        end

        it 'keeps a compact overview above the featured card and sharing in the page header' do
          get achievement_path('continent_europe')

          document = Nokogiri::HTML(response.body)
          expect(document.css('h1').size).to eq(1)
          expect(document.at_css('.ach-main h1').text).to eq('Europe Explorer')
          expect(document.at_css('.ach-set-layout > .ach-set-hero .ach-set-preview [role="button"]'))
            .to be_present
          expect(document.at_css('.ach-set-layout > #collection [role="search"]')).to be_present
          expect(document.at_css('.ach-set-header form')['action'])
            .to eq(toggle_sharing_achievement_path('continent_europe'))
          expect(document.at_css('.ach-set-header form').text).to include('Create public link')
          create_form = document.at_css('[data-card-modal-target="createForm"]')
          expect(create_form['data-action']).to eq('submit->card-modal#createPublicLink')
          expect(create_form['data-turbo']).to eq('false')
          expect(create_form.at_css('[name="enabled"]')['value']).to eq('true')
          expect(create_form['hidden']).to be_nil
          disable_form = document.at_css('[data-card-modal-target="disableForm"]')
          expect(disable_form.at_css('[name="enabled"]')['value']).to eq('false')
          expect(disable_form['hidden']).not_to be_nil
          expect(document.at_css('[data-card-modal-target="publicLink"]')['hidden']).not_to be_nil
          expect(document.at_css('.ach-set-hero > :first-child')['class']).to eq('ach-set-details')
          expect(document.at_css('.ach-set-details').text).to include('0 of 50 countries visited')
          expect(document.at_css('.ach-threshold-note').text).to include('60 minutes')
          expect(document.css('.ach-set-status, .ach-set-description, .ach-set-tools')).to be_empty
          expect(document.at_css('.ach-collection-jump')['href']).to eq('#collection')
          expect(document.at_css('#collection')['tabindex']).to eq('-1')
        end

        it 'localizes card content and modal controls in the user locale' do
          user.persist_locale!(:de)

          get achievement_path('continent_europe')

          document = Nokogiri::HTML(response.body)
          expect(document.at_css('.card-title').text).to eq('Europe-Entdecker')
          expect(document.at_css('.card-description').text).to include('allen 50 Ländern')
          expect(document.at_css('.rarity').text).to eq('Legendär')
          expect(document.at_css('.ach-modal-tools').text).to include('Teilen', 'Einbetten')
          expect(document.at_css('[data-card-modal-labels-value]')['data-card-modal-labels-value'])
            .to include('Öffentlicher Link')
          expect(document.at_css('[data-controller="card-modal"]')['data-action'])
            .to include('turbo:before-cache@document->card-modal#prepareForCache')
        end

        it 'uses native GET submission so filtering retains the collection fragment' do
          get achievement_path('continent_europe')

          form = Nokogiri::HTML(response.body).at_css('[role="search"]')
          expect(form['action']).to eq("#{achievement_path('continent_europe')}#collection")
          expect(form['method']).to eq('get')
          expect(form['data-turbo']).to eq('false')
        end

        it 'searches beyond the first page without requiring accents or matching case' do
          get achievement_path('country_br'), params: { q: 'sAo pAuLo' }

          document = Nokogiri::HTML(response.body)
          expect(document.css('.ach-child-grid .card-title').map(&:text)).to eq(['São Paulo'])
          expect(document.at_css('input[name="q"]')['value']).to eq('sAo pAuLo')
        end

        it 'filters unlocked and locked cards before pagination' do
          exploration('DE-BY' => '2026-07-01T10:00:00Z')

          get achievement_path('country_de'), params: { status: 'unlocked' }
          document = Nokogiri::HTML(response.body)
          expect(document.css('.ach-child-grid .card-title').map(&:text)).to eq(['Bavaria'])

          get achievement_path('country_de'), params: { status: 'locked' }
          expect(Nokogiri::HTML(response.body).css('.ach-child-grid .card-title').map(&:text)).not_to include('Bavaria')
        end

        it 'combines a search with the in-progress status' do
          exploration('DE' => '2026-07-01T10:00:00Z')

          get achievement_path('continent_europe'), params: { status: 'in_progress', q: 'germ' }

          document = Nokogiri::HTML(response.body)
          expect(document.css('.ach-child-grid .card-title').map(&:text)).to eq(['Germany'])
        end

        it 'offers a recovery path for an empty search and escapes the query' do
          get achievement_path('country_de'), params: { q: '<script>alert(1)</script>' }

          document = Nokogiri::HTML(response.body)
          expect(document.at_css('.ach-empty[role="status"]').text).to include('No matching cards')
          expect(document.at_css('.ach-empty a')['href']).to eq("#{achievement_path('country_de')}#collection")
          expect(response.body).not_to include('<script>alert(1)</script>')
        end

        it 'keeps search and status when paginating and falls back for an invalid status' do
          get achievement_path('continent_europe'), params: { q: 'a', status: 'locked' }

          document = Nokogiri::HTML(response.body)
          href = document.at_css('.ach-pagination a')['href']
          expect(href).to include('q=a', 'status=locked', '#collection')

          get achievement_path('continent_europe'), params: { status: 'unknown' }
          expect(Nokogiri::HTML(response.body).at_css('select[name="status"] option[selected]')['value']).to eq('all')
        end

        it 'renders a country page with its region cards' do
          exploration('DE-BY' => '2026-07-01T10:00:00Z')

          get achievement_path('country_de')

          expect(response.body).to include('Germany Explorer')
          expect(response.body).to include('Bavaria')
          expect(response.body).to include('Saxony')
        end

        it 'paginates at twelve cards with a filtered pager above the grid, earned first' do
          exploration('SE' => '2026-07-01T10:00:00Z')

          get achievement_path('continent_europe')

          expect(response.body.scan(/ach-spectral-wrap--sm/).size).to eq(12)
          expect(response.body).to include('ach-pagination')
          expect(response.body.index('Sweden')).to be < response.body.index('Albania')
          document = Nokogiri::HTML(response.body)
          expect(document.at_css('.ach-collection-header .ach-page-range').text).to include('1–12 of 50')
          expect(document.at_css('.ach-collection-header a[rel="next"]')['href']).to include('page=2', '#collection')
          expect(document.at_css('.ach-collection-header a[rel="prev"]')).to be_nil

          get achievement_path('continent_europe'), params: { page: 2, status: 'locked' }
          document = Nokogiri::HTML(response.body)
          expect(document.at_css('.ach-collection-header a[rel="next"]')['href']).to include('page=3', 'status=locked')
          expect(document.at_css('.ach-collection-header a[rel="prev"]')['href']).to include('page=1', 'status=locked')
        end

        it 'renders a continent page with country cards, linking only gridded ones' do
          exploration('DE' => '2026-07-01T10:00:00Z', 'FR' => '2026-07-02T10:00:00Z')

          get achievement_path('continent_europe')

          expect(response.body).to include('Europe Explorer')
          expect(response.body).to include(%(href="#{achievement_path('country_de')}"))
          expect(response.body).to include('France')
          expect(response.body).not_to include(%(href="#{achievement_path('country_fr')}"))
        end

        it 'renders locked regions as geometry silhouettes when shapes exist' do
          create(:region, code: 'DE-BW',
                          geom: 'MULTIPOLYGON (((8.0 47.5, 8.0 49.8, 10.5 49.8, 10.5 47.5, 8.0 47.5)))')
          exploration('DE-BY' => '2026-07-01T10:00:00Z')

          get achievement_path('country_de')

          expect(response.body).to include('ach-silhouette-svg')
          expect(response.body).not_to include('data-achievement-card-silhouette-value')
          expect(response.body).not_to include('data-controller="achievement-map"')
        end

        it 'redirects a hidden world tier page to the index' do
          get achievement_path('border_hopper')

          expect(response).to redirect_to(achievements_path)
        end

        it 'renders earned regions with the same shared spectral materials as locked ones' do
          create(:region, code: 'DE-BY',
                          geom: 'MULTIPOLYGON (((11 48, 11 49, 12 49, 12 48, 11 48)))')
          exploration('DE-BY' => '2026-07-01T10:00:00Z')

          get achievement_path('country_de')

          document = Nokogiri::HTML(response.body)
          card = document.at_css('[data-achievement-card-key-value="DE-BY"]')
          expect(card['data-achievement-card-locked-value']).to eq('false')
          expect(card['data-action']).to include('pointermove->achievement-card#move')
          expect(card.at_css('.spectral-fallback svg path')['d']).to be_present
          expect(card['data-achievement-card-silhouette-value']).to be_nil
          expect(card['data-achievement-card-paper-value']).to include('paper-pressed-fiber-v2')
          expect(card['data-achievement-card-foil-value']).to include('foil-stamped-grain-v4')
          expect(card.text).to include('Unlocked · 1 Jul 2026')
          expect(document.css('[data-controller="achievement-map"]')).to be_empty
        end

        it 'keeps locked cards previewable without pointer tilt actions' do
          get achievement_path('country_de')

          document = Nokogiri::HTML(response.body)
          card = document.at_css('.ach-child-grid [data-achievement-card-locked-value="true"]')
          expect(card).to be_present
          expect(card['data-action']).not_to include('pointermove->achievement-card#move')
          expect(card['data-action']).to include('click->card-modal#open')
          expect(card.at_css('.ach-spectral--locked')).to be_present
        end

        it 'sends a flat country to its continent instead of 404ing' do
          get achievement_path('country_fr')

          expect(response).to redirect_to(achievement_path('continent_europe'))
        end

        it 'still 404s a flat country with no continent' do
          get achievement_path('country_aq')

          expect(response).to have_http_status(:not_found)
        end

        it 'returns 404 for the old pre-rename keys' do
          get achievement_path('explorer_germany')

          expect(response).to have_http_status(:not_found)
        end

        it 'returns 404 for an unknown key' do
          get achievement_path('explorer_atlantis')

          expect(response).to have_http_status(:not_found)
        end
      end

      describe 'PATCH /achievements/:key/toggle_sharing' do
        it 'returns to the collection page after changing sharing' do
          page_url = achievement_url('country_de')

          patch toggle_sharing_achievement_path('country_de'), headers: { 'HTTP_REFERER' => page_url }

          expect(response).to redirect_to(page_url)
        end

        it 'enables sharing and generates a uuid once' do
          progress = create(:achievement_progress, user:, achievement_key: 'country_de')

          patch toggle_sharing_achievement_path('country_de')
          expect(progress.reload.sharing_enabled).to be(true)
          uuid = progress.sharing_uuid
          expect(uuid).to be_present

          patch toggle_sharing_achievement_path('country_de')
          expect(progress.reload.sharing_enabled).to be(false)
          expect(progress.sharing_uuid).to eq(uuid)
        end

        it 'serializes uuid initialization on the sharing carrier' do
          progress = create(:achievement_progress, user:, achievement_key: 'country_de')
          expect_any_instance_of(Achievements::Progress).to receive(:with_lock).and_call_original

          patch toggle_sharing_achievement_path('country_de'), params: { enabled: true }, as: :json

          expect(response.parsed_body['uuid']).to eq(progress.reload.sharing_uuid)
        end

        it 'creates the sharing carrier on demand' do
          expect { patch toggle_sharing_achievement_path('country_de') }
            .to change { user.achievement_progresses.count }.by(1)

          carrier = user.achievement_progresses.find_by(achievement_key: 'country_de')
          expect(carrier.sharing_enabled).to be(true)
          expect(carrier.state).to eq({})
        end

        it 'returns 404 for a key outside the registry' do
          patch toggle_sharing_achievement_path('explorer_atlantis')

          expect(response).to have_http_status(:not_found)
        end

        it 'recovers when a concurrent request creates the carrier first' do
          carrier = create(:achievement_progress, user:, achievement_key: 'country_de')
          allow_any_instance_of(ActiveRecord::Relation).to receive(:find_or_create_by!)
            .and_raise(ActiveRecord::RecordNotUnique,
                       'index_achievement_progresses_on_user_id_and_achievement_key')

          patch toggle_sharing_achievement_path('country_de')

          expect(response).to have_http_status(:redirect)
          expect(carrier.reload.sharing_enabled).to be(true)
        end

        it 'returns the sharing state and public url as JSON' do
          patch toggle_sharing_achievement_path('country_de'), as: :json

          expect(response).to have_http_status(:ok)
          body = response.parsed_body
          uuid = user.achievement_progresses.find_by(achievement_key: 'country_de').sharing_uuid
          expect(body['enabled']).to be(true)
          expect(body['uuid']).to eq(uuid)
          expect(body['url']).to end_with("/shared/achievements/#{uuid}")
        end

        it 'honors an explicit desired state and nulls the url when disabled' do
          patch toggle_sharing_achievement_path('country_de'), params: { enabled: false }, as: :json
          expect(response.parsed_body).to include('enabled' => false, 'url' => nil)

          patch toggle_sharing_achievement_path('country_de'), params: { enabled: false }, as: :json
          expect(response.parsed_body['enabled']).to be(false) # idempotent, not a blind toggle

          patch toggle_sharing_achievement_path('country_de'), params: { enabled: true }, as: :json
          body = response.parsed_body
          expect(body['enabled']).to be(true)
          expect(body['url']).to be_present
        end
      end
    end

    context 'when the feature flag is disabled' do
      it 'redirects to root' do
        get achievements_path

        expect(response).to redirect_to(root_path)
      end
    end
  end
end
