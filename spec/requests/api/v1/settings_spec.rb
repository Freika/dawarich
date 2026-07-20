# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Settings', type: :request do
  let!(:user) { create(:user) }
  let!(:api_key) { user.api_key }

  describe 'GET /index' do
    it 'returns settings including timezone' do
      get "/api/v1/settings?api_key=#{api_key}"

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['settings']['timezone']).to eq('UTC')
    end

    it 'returns custom timezone when set' do
      user.settings['timezone'] = 'America/New_York'
      user.save!

      get "/api/v1/settings?api_key=#{api_key}"

      expect(response.parsed_body['settings']['timezone']).to eq('America/New_York')
    end
  end

  describe 'PATCH /update' do
    context 'with valid request' do
      it 'returns http success' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 0.3 } }

        expect(response).to have_http_status(:success)
      end

      it 'updates the settings' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 0.3 } }

        expect(user.reload.settings['route_opacity'].to_f).to eq(0.3)
      end

      it 'returns the updated settings' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 0.3 } }

        expect(response.parsed_body['settings']['route_opacity'].to_f).to eq(0.3)
      end

      it 'updates timezone' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { timezone: 'Europe/Berlin' } }

        expect(response).to have_http_status(:success)
        expect(user.reload.timezone).to eq('Europe/Berlin')
      end

      it 'returns updated timezone in response' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { timezone: 'Asia/Tokyo' } }

        expect(response.parsed_body['settings']['timezone']).to eq('Asia/Tokyo')
      end

      it 'rejects invalid timezone values' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { timezone: 'Invalid/Zone' } }

        expect(response).to have_http_status(:success)
        expect(user.reload.timezone).to eq('UTC')
      end

      it 'updates fog_of_war_mode' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { fog_of_war_mode: 'hexagons' } }

        expect(response).to have_http_status(:success)
        expect(user.reload.safe_settings.fog_of_war_mode).to eq('hexagons')
      end

      it 'normalizes unknown fog_of_war_mode values to points' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { fog_of_war_mode: 'octagons' } }

        expect(response).to have_http_status(:success)
        expect(user.reload.safe_settings.fog_of_war_mode).to eq('points')
      end

      it 'updates maps_maplibre_custom_theme' do
        theme = {
          base: 'blueprint',
          tokens: {
            bg: '#1E3A5F', water: '#152C4A', parks: '#1A3557',
            road_motorway: '#FFFFFF', road_primary: '#E8F0F8',
            road_secondary: '#C4D4E4', road_tertiary: '#A0B8CC',
            road_residential: '#7A94AC', road_default: '#8AA4BC'
          }
        }

        patch "/api/v1/settings?api_key=#{api_key}",
              params: { settings: { maps_maplibre_style: 'custom', maps_maplibre_custom_theme: theme } }

        expect(response).to have_http_status(:success)

        stored = user.reload.safe_settings.maps_maplibre_custom_theme
        expect(stored['base']).to eq('blueprint')
        expect(stored['tokens']['bg']).to eq('#1E3A5F')
        expect(user.safe_settings.maps_maplibre_style).to eq('custom')
      end

      it 'updates route_color and track_color' do
        patch "/api/v1/settings?api_key=#{api_key}",
              params: { settings: { route_color: '#123456', track_color: '#654321' } }

        expect(response).to have_http_status(:success)
        expect(user.reload.safe_settings.route_color).to eq('#123456')
        expect(user.safe_settings.track_color).to eq('#654321')
      end

      it 'persists Places tag filters across map reconnects' do
        filters = [11, 'untagged']

        patch "/api/v1/settings?api_key=#{api_key}",
              params: { settings: { places_tag_filters: filters } }

        expect(response).to have_http_status(:success)
        expect(user.reload.safe_settings.places_tag_filters).to eq(filters)
        expect(response.parsed_body.dig('settings', 'places_tag_filters')).to eq(filters)
      end

      it 'updates maps_maplibre_tiles_url' do
        patch "/api/v1/settings?api_key=#{api_key}",
              params: { settings: { maps_maplibre_tiles_url: 'https://tiles.example.com/{z}/{x}/{y}.mvt' } }

        expect(response).to have_http_status(:success)
        expect(user.reload.safe_settings.maps_maplibre_tiles_url)
          .to eq('https://tiles.example.com/{z}/{x}/{y}.mvt')
      end

      it 'rejects a maps_maplibre_tiles_url missing a coordinate placeholder' do
        patch "/api/v1/settings?api_key=#{api_key}",
              params: { settings: { maps_maplibre_tiles_url: 'https://tiles.example.com/{z}.mvt' } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['errors']).to include('Tile URL must include {z}, {x}, and {y} placeholders')
        expect(user.reload.safe_settings.maps_maplibre_tiles_url).to be_nil
      end

      it 'rejects a non-string maps_maplibre_tiles_url without raising' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { maps_maplibre_tiles_url: 123 } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(user.reload.safe_settings.maps_maplibre_tiles_url).to be_nil
      end

      it 'normalizes a whitespace-only maps_maplibre_tiles_url to nil' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { maps_maplibre_tiles_url: '   ' } }

        expect(response).to have_http_status(:success)
        expect(user.reload.safe_settings.maps_maplibre_tiles_url).to be_nil
      end

      it 'merges nested maps settings without clobbering v1 keys' do
        user.settings['maps'] = {
          'name' => 'OSM', 'url' => +'https://tile.example/{z}/{x}/{y}.png', 'distance_unit' => 'km'
        }
        user.save!

        patch "/api/v1/settings?api_key=#{api_key}",
              params: {
                settings: {
                  maps: {
                    distance_unit: 'mi',
                    hidden_tile_categories: ['roads'],
                    disabled_poi_groups: ['shopping']
                  }
                }
              }

        expect(response).to have_http_status(:success)

        maps = user.reload.settings['maps']
        expect(maps['name']).to eq('OSM')
        expect(maps['url']).to eq('https://tile.example/{z}/{x}/{y}.png')
        expect(maps['distance_unit']).to eq('mi')
        expect(maps['hidden_tile_categories']).to eq(['roads'])
        expect(maps['disabled_poi_groups']).to eq(['shopping'])
      end

      context 'when user is on the lite plan (cloud)' do
        let!(:lite_user) do
          u = create(:user)
          u.update_columns(plan: User.plans[:lite])
          u
        end
        let(:lite_api_key) { lite_user.api_key }

        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        end

        it 'does not persist map customization settings' do
          patch "/api/v1/settings?api_key=#{lite_api_key}",
                params: {
                  settings: {
                    maps_maplibre_style: 'custom',
                    maps_maplibre_tiles_url: 'https://tiles.example.com/{z}/{x}/{y}.mvt',
                    route_color: '#123456',
                    track_color: '#654321',
                    maps_maplibre_custom_theme: { base: 'blueprint', tokens: { bg: '#111111' } }
                  }
                }

          expect(response).to have_http_status(:success)

          settings = lite_user.reload.safe_settings
          expect(settings.maps_maplibre_style).to eq('light')
          expect(settings.maps_maplibre_tiles_url).to be_nil
          expect(settings.route_color).to eq('#0000ff')
          expect(settings.track_color).to eq('#6366F1')
          expect(settings.maps_maplibre_custom_theme['base']).to eq('noir')
        end

        it 'still persists built-in style switches' do
          patch "/api/v1/settings?api_key=#{lite_api_key}",
                params: { settings: { maps_maplibre_style: 'dark' } }

          expect(response).to have_http_status(:success)
          expect(lite_user.reload.safe_settings.maps_maplibre_style).to eq('dark')
        end
      end

      it 'returns maps_maplibre_custom_theme in the settings payload' do
        get "/api/v1/settings?api_key=#{api_key}"

        theme = response.parsed_body['settings']['maps_maplibre_custom_theme']
        expect(theme['base']).to eq('noir')
        expect(theme['tokens']['bg']).to eq('#000000')
      end

      it 'updates stay_max_gap_minutes' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { stay_max_gap_minutes: 90 } }

        expect(response).to have_http_status(:success)
        expect(user.reload.safe_settings.stay_max_gap_minutes).to eq(90)
      end

      it 'returns updated stay_max_gap_minutes in response' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { stay_max_gap_minutes: 90 } }

        expect(response.parsed_body['settings']['stay_max_gap_minutes']).to eq(90)
      end

      it 'clamps stay_max_gap_minutes above the maximum on read' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { stay_max_gap_minutes: 1000 } }

        expect(response.parsed_body['settings']['stay_max_gap_minutes']).to eq(720)
      end

      it 'clamps stay_max_gap_minutes below the minimum on read' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { stay_max_gap_minutes: 1 } }

        expect(response.parsed_body['settings']['stay_max_gap_minutes']).to eq(5)
      end

      it 'preserves stay_max_gap_minutes when a patch omits it' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { stay_max_gap_minutes: 90 } }
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 0.3 } }

        expect(user.reload.safe_settings.stay_max_gap_minutes).to eq(90)
      end

      context 'when user is inactive' do
        before do
          user.update(status: :inactive, active_until: 1.day.ago)
        end

        it 'returns http unauthorized' do
          patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 0.3 } }

          expect(response).to have_http_status(:unauthorized)
        end
      end

      context 'when user is inactive but active_until is in the future' do
        before do
          user.update(status: :inactive, active_until: 1.day.from_now)
        end

        it 'returns http unauthorized' do
          patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 0.3 } }

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end

    context 'with invalid request' do
      before do
        allow_any_instance_of(User).to receive(:save).and_return(false)
      end

      it 'returns http unprocessable entity' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 'invalid' } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns an error message' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 'invalid' } }

        expect(response.parsed_body['message']).to eq('Something went wrong')
      end
    end

    context 'with transportation thresholds' do
      let(:threshold_params) do
        {
          settings: {
            transportation_thresholds: {
              walking_max_speed: 8,
              cycling_max_speed: 50
            }
          }
        }
      end

      it 'triggers recalculation when thresholds change' do
        expect do
          patch "/api/v1/settings?api_key=#{api_key}", params: threshold_params
        end.to have_enqueued_job(Tracks::TransportationModeRecalculationJob).with(user.id)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['recalculation_triggered']).to be true
      end

      context 'when recalculation is in progress' do
        before do
          Tracks::TransportationRecalculationStatus.new(user.id).start(total_tracks: 100)
        end

        it 'returns locked status' do
          patch "/api/v1/settings?api_key=#{api_key}", params: threshold_params

          expect(response).to have_http_status(:locked)
          expect(response.parsed_body['status']).to eq('locked')
        end
      end
    end
  end

  describe 'PATCH /api/v1/settings with enabled_transportation_modes' do
    it 'persists a valid allowlist' do
      patch "/api/v1/settings?api_key=#{api_key}",
            params: { settings: { enabled_transportation_modes: %w[walking cycling] } }

      expect(response).to have_http_status(:success)
      expect(user.reload.settings['enabled_transportation_modes']).to eq(%w[walking cycling])
    end

    it 'returns 422 on empty intersection' do
      patch "/api/v1/settings?api_key=#{api_key}",
            params: { settings: { enabled_transportation_modes: %w[bogus] } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors']).to include(/Enable at least one transportation mode/i)
    end
  end

  describe 'GET /transportation_recalculation_status' do
    it 'returns idle status when no recalculation is running' do
      get "/api/v1/settings/transportation_recalculation_status?api_key=#{api_key}"

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('idle')
    end

    it 'returns processing status when recalculation is in progress' do
      status = Tracks::TransportationRecalculationStatus.new(user.id)
      status.start(total_tracks: 100)
      status.update_progress(processed_tracks: 50, total_tracks: 100)

      get "/api/v1/settings/transportation_recalculation_status?api_key=#{api_key}"

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('processing')
      expect(response.parsed_body['total_tracks']).to eq(100)
      expect(response.parsed_body['processed_tracks']).to eq(50)
    end
  end

  describe 'PATCH /update with maps.distance_unit' do
    it 'updates the distance unit' do
      patch "/api/v1/settings?api_key=#{api_key}",
            params: { settings: { maps: { distance_unit: 'mi' } } }

      expect(response).to have_http_status(:success)
      expect(user.reload.settings.dig('maps', 'distance_unit')).to eq('mi')
      expect(response.parsed_body['settings']['distance_unit']).to eq('mi')
    end

    it 'preserves other maps subkeys' do
      user.settings['maps'] = { 'distance_unit' => 'km', 'hidden_tile_categories' => ['poi'] }
      user.save!

      patch "/api/v1/settings?api_key=#{api_key}",
            params: { settings: { maps: { distance_unit: 'mi' } } }

      expect(user.reload.settings.dig('maps', 'hidden_tile_categories')).to eq(['poi'])
    end

    it 'rejects invalid distance units' do
      user.settings['maps'] = { 'distance_unit' => 'km' }
      user.save!

      patch "/api/v1/settings?api_key=#{api_key}",
            params: { settings: { maps: { distance_unit: 'banana' } } }

      expect(response).to have_http_status(:success)
      expect(user.reload.settings.dig('maps', 'distance_unit')).to eq('km')
    end

    it 'ignores maps sent as an array' do
      user.settings['maps'] = { 'distance_unit' => 'km' }
      user.save!

      patch "/api/v1/settings?api_key=#{api_key}",
            params: { settings: { maps: [{ distance_unit: 'mi' }] } }

      expect(response).to have_http_status(:success)
      expect(user.reload.settings['maps']).to eq('distance_unit' => 'km')
    end
  end
end
