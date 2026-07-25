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
      end

      describe 'GET /achievements/:key' do
        it 'renders a country page with its region cards' do
          exploration('DE-BY' => '2026-07-01T10:00:00Z')

          get achievement_path('country_de')

          expect(response.body).to include('Germany Explorer')
          expect(response.body).to include('Bavaria')
          expect(response.body).to include('Saxony')
        end

        it 'paginates a continent page at ten cards, earned first' do
          exploration('SE' => '2026-07-01T10:00:00Z')

          get achievement_path('continent_europe')

          expect(response.body.scan(/ach-card--sm/).size).to eq(10)
          expect(response.body).to include('ach-pagination')
          expect(response.body.index('Sweden')).to be < response.body.index('Albania')
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

          expect(response.body).to include('ach-art-silhouette')
        end

        it 'redirects a hidden world tier page to the index' do
          get achievement_path('border_hopper')

          expect(response).to redirect_to(achievements_path)
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
