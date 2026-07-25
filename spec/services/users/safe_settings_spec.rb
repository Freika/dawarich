# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::SafeSettings do
  describe '#config' do
    context 'with default values' do
      let(:settings) { {} }
      let(:safe_settings) { described_class.new(settings) }

      it 'returns default configuration' do
        expect(safe_settings.config).to eq(
          {
            fog_of_war_meters: 50,
            meters_between_routes: 500,
            preferred_map_layer: 'OpenStreetMap',
            speed_colored_routes: false,
            points_rendering_mode: 'raw',
            minutes_between_routes: 30,
            time_threshold_minutes: 30,
            merge_threshold_minutes: 15,
            live_map_enabled: true,
            route_opacity: 0.6,
            route_color: '#0000ff',
            track_color: '#6366F1',
            immich_url: nil,
            immich_api_key: nil,
            photoprism_url: nil,
            photoprism_api_key: nil,
            airtrail_url: nil,
            airtrail_api_key: nil,
            maps: { 'distance_unit' => 'km' },
            distance_unit: 'km',
            visits_suggestions_enabled: true,
            speed_color_scale: nil,
            fog_of_war_threshold: 50,
          fog_of_war_mode: 'points',
            enabled_map_layers: %w[Tracks Heatmap],
            places_tag_filters: nil,
            maps_maplibre_style: 'light',
            maps_maplibre_tiles_url: nil,
            maps_maplibre_custom_theme: {
              'base' => 'noir',
              'tokens' => {
                'bg' => '#000000', 'water' => '#0A0A0A', 'parks' => '#111111',
                'buildings' => '#141414', 'railway' => '#808080', 'boundaries' => '#4D4D4D',
                'road_motorway' => '#FFFFFF', 'road_primary' => '#E0E0E0',
                'road_secondary' => '#B0B0B0', 'road_tertiary' => '#808080',
                'road_residential' => '#505050', 'road_default' => '#808080'
              }
            },
            globe_projection: true,
            transportation_thresholds: {
              'walking_max_speed' => 7,
              'cycling_max_speed' => 45,
              'driving_max_speed' => 220,
              'flying_min_speed' => 150
            },
            transportation_expert_thresholds: {
              'stationary_max_speed' => 1,
              'running_vs_cycling_accel' => 0.25,
              'cycling_vs_driving_accel' => 0.4,
              'train_min_speed' => 80,
              'min_segment_duration' => 60,
              'time_gap_threshold' => 180,
              'min_flight_distance_km' => 100
            },
            enabled_transportation_modes: Track::TRANSPORTATION_MODES.keys.map(&:to_s),
            transportation_expert_mode: false,
            min_minutes_spent_in_city: 60,
            max_gap_minutes_in_city: 120,
            gps_filtering_enabled: true,
            gps_accuracy_threshold: 100,
            timezone: 'UTC',
            visit_radius_meters: 100,
            visit_min_points: 3,
            visit_min_duration_minutes: 5,
            visit_density_fill_enabled: true,
            stay_max_gap_minutes: 60
          }
        )
      end
    end

    context 'with custom values' do
      let(:settings) do
        {
          'fog_of_war_meters' => 100,
          'meters_between_routes' => 1000,
          'preferred_map_layer' => 'Satellite',
          'speed_colored_routes' => true,
          'points_rendering_mode' => 'simplified',
          'minutes_between_routes' => 60,
          'time_threshold_minutes' => 45,
          'merge_threshold_minutes' => 20,
          'live_map_enabled' => false,
          'route_opacity' => 80,
          'immich_url' => 'https://immich.example.com',
          'immich_api_key' => 'immich-key',
          'photoprism_url' => 'https://photoprism.example.com',
          'photoprism_api_key' => 'photoprism-key',
          'maps' => { 'name' => 'custom', 'url' => 'https://custom.example.com' },
          'visits_suggestions_enabled' => false,
          'enabled_map_layers' => %w[Points Routes Areas Photos]
        }
      end
      let(:safe_settings) { described_class.new(settings) }

      it 'returns custom configuration' do
        expect(safe_settings.settings).to eq(
          {
            'fog_of_war_meters' => 100,
            'fog_of_war_threshold' => 50,
          'fog_of_war_mode' => 'points',
            'meters_between_routes' => 1000,
            'preferred_map_layer' => 'Satellite',
            'speed_colored_routes' => true,
            'points_rendering_mode' => 'simplified',
            'minutes_between_routes' => 60,
            'time_threshold_minutes' => 45,
            'merge_threshold_minutes' => 20,
            'live_map_enabled' => false,
            'route_opacity' => 80,
            'route_color' => '#0000ff',
            'track_color' => '#6366F1',
            'immich_url' => 'https://immich.example.com',
            'immich_api_key' => 'immich-key',
            'immich_skip_ssl_verification' => false,
            'photoprism_url' => 'https://photoprism.example.com',
            'photoprism_api_key' => 'photoprism-key',
            'photoprism_skip_ssl_verification' => false,
            'airtrail_url' => nil,
            'airtrail_api_key' => nil,
            'airtrail_skip_ssl_verification' => false,
            'airtrail_last_synced_at' => nil,
            'maps' => { 'distance_unit' => 'km', 'name' => 'custom', 'url' => 'https://custom.example.com' },
            'visits_suggestions_enabled' => false,
            'enabled_map_layers' => %w[Points Routes Areas Photos],
            'maps_maplibre_style' => 'light',
            'maps_maplibre_tiles_url' => nil,
            'maps_maplibre_custom_theme' => {
              'base' => 'noir',
              'tokens' => {
                'bg' => '#000000', 'water' => '#0A0A0A', 'parks' => '#111111',
                'buildings' => '#141414', 'railway' => '#808080', 'boundaries' => '#4D4D4D',
                'road_motorway' => '#FFFFFF', 'road_primary' => '#E0E0E0',
                'road_secondary' => '#B0B0B0', 'road_tertiary' => '#808080',
                'road_residential' => '#505050', 'road_default' => '#808080'
              }
            },
            'news_emails_enabled' => true,
            'globe_projection' => true,
            'supporter_email' => nil,
            'supporter_github_username' => nil,
            'show_supporter_badge' => true,
            'transportation_thresholds' => {
              'walking_max_speed' => 7,
              'cycling_max_speed' => 45,
              'driving_max_speed' => 220,
              'flying_min_speed' => 150
            },
            'transportation_expert_thresholds' => {
              'stationary_max_speed' => 1,
              'running_vs_cycling_accel' => 0.25,
              'cycling_vs_driving_accel' => 0.4,
              'train_min_speed' => 80,
              'min_segment_duration' => 60,
              'time_gap_threshold' => 180,
              'min_flight_distance_km' => 100
            },
            'transportation_expert_mode' => false,
            'min_minutes_spent_in_city' => 60,
            'max_gap_minutes_in_city' => 120,
            'gps_filtering_enabled' => true,
            'gps_accuracy_threshold' => 100,
            'timezone' => 'UTC',
            'visit_radius_meters' => 100,
            'visit_min_points' => 3,
            'visit_min_duration_minutes' => 5,
            'visit_density_fill_enabled' => true,
            'stay_max_gap_minutes' => 60
          }
        )
      end

      it 'returns custom config configuration' do
        expect(safe_settings.config).to eq(
          {
            fog_of_war_meters: 100,
            meters_between_routes: 1000,
            preferred_map_layer: 'Satellite',
            speed_colored_routes: true,
            points_rendering_mode: 'simplified',
            minutes_between_routes: 60,
            time_threshold_minutes: 45,
            merge_threshold_minutes: 20,
            live_map_enabled: false,
            route_opacity: 80,
            route_color: '#0000ff',
            track_color: '#6366F1',
            immich_url: 'https://immich.example.com',
            immich_api_key: 'immich-key',
            photoprism_url: 'https://photoprism.example.com',
            photoprism_api_key: 'photoprism-key',
            airtrail_url: nil,
            airtrail_api_key: nil,
            maps: { 'distance_unit' => 'km', 'name' => 'custom', 'url' => 'https://custom.example.com' },
            distance_unit: 'km',
            visits_suggestions_enabled: false,
            speed_color_scale: nil,
            fog_of_war_threshold: 50,
          fog_of_war_mode: 'points',
            enabled_map_layers: %w[Points Routes Areas Photos],
            places_tag_filters: nil,
            maps_maplibre_style: 'light',
            maps_maplibre_tiles_url: nil,
            maps_maplibre_custom_theme: {
              'base' => 'noir',
              'tokens' => {
                'bg' => '#000000', 'water' => '#0A0A0A', 'parks' => '#111111',
                'buildings' => '#141414', 'railway' => '#808080', 'boundaries' => '#4D4D4D',
                'road_motorway' => '#FFFFFF', 'road_primary' => '#E0E0E0',
                'road_secondary' => '#B0B0B0', 'road_tertiary' => '#808080',
                'road_residential' => '#505050', 'road_default' => '#808080'
              }
            },
            globe_projection: true,
            transportation_thresholds: {
              'walking_max_speed' => 7,
              'cycling_max_speed' => 45,
              'driving_max_speed' => 220,
              'flying_min_speed' => 150
            },
            transportation_expert_thresholds: {
              'stationary_max_speed' => 1,
              'running_vs_cycling_accel' => 0.25,
              'cycling_vs_driving_accel' => 0.4,
              'train_min_speed' => 80,
              'min_segment_duration' => 60,
              'time_gap_threshold' => 180,
              'min_flight_distance_km' => 100
            },
            enabled_transportation_modes: Track::TRANSPORTATION_MODES.keys.map(&:to_s),
            transportation_expert_mode: false,
            min_minutes_spent_in_city: 60,
            max_gap_minutes_in_city: 120,
            gps_filtering_enabled: true,
            gps_accuracy_threshold: 100,
            timezone: 'UTC',
            visit_radius_meters: 100,
            visit_min_points: 3,
            visit_min_duration_minutes: 5,
            visit_density_fill_enabled: true,
            stay_max_gap_minutes: 60
          }
        )
      end
    end
  end

  describe '#timezone' do
    let(:safe_settings) { described_class.new(settings) }

    context 'when timezone is not set' do
      let(:settings) { {} }

      it 'returns default UTC timezone' do
        expect(safe_settings.timezone).to eq('UTC')
      end
    end

    context 'when timezone is explicitly set' do
      let(:settings) { { 'timezone' => 'America/New_York' } }

      it 'returns the custom timezone' do
        expect(safe_settings.timezone).to eq('America/New_York')
      end
    end

    context 'when timezone is set to Tokyo' do
      let(:settings) { { 'timezone' => 'Asia/Tokyo' } }

      it 'returns the Tokyo timezone' do
        expect(safe_settings.timezone).to eq('Asia/Tokyo')
      end
    end
  end

  describe 'individual settings' do
    let(:safe_settings) { described_class.new(settings) }

    context 'with default values' do
      let(:settings) { {} }

      it 'returns default values for each setting' do
        expect(safe_settings.fog_of_war_meters).to eq(50)
        expect(safe_settings.meters_between_routes).to eq(500)
        expect(safe_settings.preferred_map_layer).to eq('OpenStreetMap')
        expect(safe_settings.speed_colored_routes).to be false
        expect(safe_settings.points_rendering_mode).to eq('raw')
        expect(safe_settings.minutes_between_routes).to eq(30)
        expect(safe_settings.time_threshold_minutes).to eq(30)
        expect(safe_settings.merge_threshold_minutes).to eq(15)
        expect(safe_settings.live_map_enabled).to be true
        expect(safe_settings.route_opacity).to eq(0.6)
        expect(safe_settings.immich_url).to be_nil
        expect(safe_settings.immich_api_key).to be_nil
        expect(safe_settings.photoprism_url).to be_nil
        expect(safe_settings.photoprism_api_key).to be_nil
        expect(safe_settings.maps).to eq({ 'distance_unit' => 'km' })
        expect(safe_settings.visits_suggestions_enabled?).to be true
        expect(safe_settings.enabled_map_layers).to eq(%w[Tracks Heatmap])
        expect(safe_settings.timezone).to eq('UTC')
      end
    end

    context 'with custom values' do
      let(:settings) do
        {
          'fog_of_war_meters' => 100,
          'meters_between_routes' => 1000,
          'preferred_map_layer' => 'Satellite',
          'speed_colored_routes' => true,
          'points_rendering_mode' => 'simplified',
          'minutes_between_routes' => 60,
          'time_threshold_minutes' => 45,
          'merge_threshold_minutes' => 20,
          'live_map_enabled' => false,
          'route_opacity' => 80,
          'immich_url' => 'https://immich.example.com',
          'immich_api_key' => 'immich-key',
          'photoprism_url' => 'https://photoprism.example.com',
          'photoprism_api_key' => 'photoprism-key',
          'maps' => { 'name' => 'custom', 'url' => 'https://custom.example.com' },
          'visits_suggestions_enabled' => false,
          'enabled_map_layers' => ['Points', 'Tracks', 'Fog of War', 'Suggested Visits']
        }
      end

      it 'returns custom values for each setting' do
        expect(safe_settings.fog_of_war_meters).to eq(100)
        expect(safe_settings.meters_between_routes).to eq(1000)
        expect(safe_settings.preferred_map_layer).to eq('Satellite')
        expect(safe_settings.speed_colored_routes).to be true
        expect(safe_settings.points_rendering_mode).to eq('simplified')
        expect(safe_settings.minutes_between_routes).to eq(60)
        expect(safe_settings.time_threshold_minutes).to eq(45)
        expect(safe_settings.merge_threshold_minutes).to eq(20)
        expect(safe_settings.live_map_enabled).to be false
        expect(safe_settings.route_opacity).to eq(80)
        expect(safe_settings.immich_url).to eq('https://immich.example.com')
        expect(safe_settings.immich_api_key).to eq('immich-key')
        expect(safe_settings.photoprism_url).to eq('https://photoprism.example.com')
        expect(safe_settings.photoprism_api_key).to eq('photoprism-key')
        expect(safe_settings.maps).to eq({ 'distance_unit' => 'km', 'name' => 'custom',
'url' => 'https://custom.example.com' })
        expect(safe_settings.visits_suggestions_enabled?).to be false
        expect(safe_settings.enabled_map_layers).to eq(['Points', 'Tracks', 'Fog of War', 'Suggested Visits'])
      end
    end
  end

  describe '#distance_unit' do
    let(:safe_settings) { described_class.new(settings) }

    context 'when maps key exists without distance_unit' do
      let(:settings) { { 'maps' => { 'name' => 'custom' } } }

      it 'falls back to the default distance unit' do
        expect(safe_settings.distance_unit).to eq('km')
      end
    end

    context 'when maps key is explicitly set to nil' do
      let(:settings) { { 'maps' => nil } }

      it 'falls back to the default distance unit' do
        expect(safe_settings.distance_unit).to eq('km')
      end
    end

    context 'when distance_unit is explicitly set' do
      let(:settings) { { 'maps' => { 'distance_unit' => 'mi' } } }

      it 'returns the custom distance unit' do
        expect(safe_settings.distance_unit).to eq('mi')
      end
    end
  end

  describe '#news_emails_enabled?' do
    let(:safe_settings) { described_class.new(settings) }

    context 'when not set' do
      let(:settings) { {} }

      it 'defaults to true' do
        expect(safe_settings.news_emails_enabled?).to be true
      end
    end

    context 'when explicitly set to true' do
      let(:settings) { { 'news_emails_enabled' => true } }

      it 'returns true' do
        expect(safe_settings.news_emails_enabled?).to be true
      end
    end

    context 'when set to false' do
      let(:settings) { { 'news_emails_enabled' => false } }

      it 'returns false' do
        expect(safe_settings.news_emails_enabled?).to be false
      end
    end
  end

  describe 'plan-aware filtering' do
    describe '#enabled_map_layers' do
      context 'when plan is lite' do
        let(:settings) { { 'enabled_map_layers' => ['Tracks', 'Heatmap', 'Fog of War', 'Scratch map', 'Points'] } }
        let(:safe_settings) { described_class.new(settings, plan: :lite) }

        it 'excludes gated layers' do
          expect(safe_settings.enabled_map_layers).to eq(%w[Tracks Points])
        end
      end

      context 'when plan is lite and only gated layers are enabled' do
        let(:settings) { { 'enabled_map_layers' => ['Heatmap', 'Fog of War', 'Scratch map'] } }
        let(:safe_settings) { described_class.new(settings, plan: :lite) }

        it 'returns empty array' do
          expect(safe_settings.enabled_map_layers).to eq([])
        end
      end

      context 'when plan is pro' do
        let(:settings) { { 'enabled_map_layers' => ['Tracks', 'Heatmap', 'Fog of War', 'Scratch map'] } }
        let(:safe_settings) { described_class.new(settings, plan: :pro) }

        it 'returns all layers as stored' do
          expect(safe_settings.enabled_map_layers).to eq(['Tracks', 'Heatmap', 'Fog of War', 'Scratch map'])
        end
      end

      context 'when plan is pro (self-hosted users always have pro)' do
        let(:settings) { { 'enabled_map_layers' => ['Tracks', 'Heatmap', 'Fog of War'] } }
        let(:safe_settings) { described_class.new(settings, plan: :pro) }

        it 'returns all layers as stored' do
          expect(safe_settings.enabled_map_layers).to eq(['Tracks', 'Heatmap', 'Fog of War'])
        end
      end

      context 'when plan is nil (backward compat)' do
        let(:settings) { { 'enabled_map_layers' => ['Tracks', 'Heatmap', 'Fog of War'] } }
        let(:safe_settings) { described_class.new(settings) }

        it 'returns all layers as stored' do
          expect(safe_settings.enabled_map_layers).to eq(['Tracks', 'Heatmap', 'Fog of War'])
        end
      end
    end

    describe '#globe_projection' do
      context 'when plan is lite' do
        let(:settings) { { 'globe_projection' => true } }
        let(:safe_settings) { described_class.new(settings, plan: :lite) }

        it 'returns false regardless of stored value' do
          expect(safe_settings.globe_projection).to be false
        end
      end

      context 'when plan is pro' do
        let(:settings) { { 'globe_projection' => true } }
        let(:safe_settings) { described_class.new(settings, plan: :pro) }

        it 'returns the stored value' do
          expect(safe_settings.globe_projection).to be true
        end
      end

      context 'when plan is nil (backward compat)' do
        let(:settings) { { 'globe_projection' => true } }
        let(:safe_settings) { described_class.new(settings) }

        it 'returns the stored value' do
          expect(safe_settings.globe_projection).to be true
        end
      end

      context 'when no value is stored' do
        context 'and plan is pro' do
          let(:safe_settings) { described_class.new({}, plan: :pro) }

          it 'defaults to true' do
            expect(safe_settings.globe_projection).to be true
          end
        end

        context 'and plan is lite' do
          let(:safe_settings) { described_class.new({}, plan: :lite) }

          it 'stays false' do
            expect(safe_settings.globe_projection).to be false
          end
        end
      end

      context 'when a pro user explicitly opted out' do
        let(:safe_settings) { described_class.new({ 'globe_projection' => false }, plan: :pro) }

        it 'preserves the stored false' do
          expect(safe_settings.globe_projection).to be false
        end
      end
    end
  end

  describe '#monthly_digest_emails_enabled?' do
    let(:safe_settings) { described_class.new(settings) }

    context 'when not set' do
      let(:settings) { {} }

      it 'returns true when the setting is missing' do
        expect(safe_settings.monthly_digest_emails_enabled?).to be true
      end
    end

    context 'when explicitly set to true' do
      let(:settings) { { 'monthly_digest_emails_enabled' => true } }

      it 'returns true when explicitly true' do
        expect(safe_settings.monthly_digest_emails_enabled?).to be true
      end
    end

    context 'when set to false' do
      let(:settings) { { 'monthly_digest_emails_enabled' => false } }

      it 'returns false when explicitly false' do
        expect(safe_settings.monthly_digest_emails_enabled?).to be false
      end
    end

    context 'when only the legacy digest_emails_enabled key is present' do
      context 'and legacy is true' do
        let(:settings) { { 'digest_emails_enabled' => true } }

        it 'falls back to legacy value (true)' do
          expect(safe_settings.monthly_digest_emails_enabled?).to be true
        end
      end

      context 'and legacy is false (preserved opt-out)' do
        let(:settings) { { 'digest_emails_enabled' => false } }

        it 'falls back to legacy value (false)' do
          expect(safe_settings.monthly_digest_emails_enabled?).to be false
        end
      end
    end

    context 'when both new and legacy keys are present' do
      let(:settings) { { 'monthly_digest_emails_enabled' => false, 'digest_emails_enabled' => true } }

      it 'prefers the new key over the legacy key' do
        expect(safe_settings.monthly_digest_emails_enabled?).to be false
      end
    end
  end

  describe '#yearly_digest_emails_enabled?' do
    let(:safe_settings) { described_class.new(settings) }

    context 'when not set' do
      let(:settings) { {} }

      it 'returns true when the setting is missing' do
        expect(safe_settings.yearly_digest_emails_enabled?).to be true
      end
    end

    context 'when set to false' do
      let(:settings) { { 'yearly_digest_emails_enabled' => false } }

      it 'returns false when explicitly false' do
        expect(safe_settings.yearly_digest_emails_enabled?).to be false
      end
    end

    context 'when only the legacy digest_emails_enabled key is present' do
      context 'and legacy is true' do
        let(:settings) { { 'digest_emails_enabled' => true } }

        it 'falls back to legacy value (true)' do
          expect(safe_settings.yearly_digest_emails_enabled?).to be true
        end
      end

      context 'and legacy is false (preserved opt-out)' do
        let(:settings) { { 'digest_emails_enabled' => false } }

        it 'falls back to legacy value (false)' do
          expect(safe_settings.yearly_digest_emails_enabled?).to be false
        end
      end
    end

    context 'when both new and legacy keys are present' do
      let(:settings) { { 'yearly_digest_emails_enabled' => false, 'digest_emails_enabled' => true } }

      it 'prefers the new key over the legacy key' do
        expect(safe_settings.yearly_digest_emails_enabled?).to be false
      end
    end
  end

  describe 'transportation threshold settings' do
    let(:safe_settings) { described_class.new(settings) }

    context 'with default values' do
      let(:settings) { {} }

      it 'returns default transportation thresholds' do
        expect(safe_settings.transportation_thresholds).to eq(
          {
            'walking_max_speed' => 7,
            'cycling_max_speed' => 45,
            'driving_max_speed' => 220,
            'flying_min_speed' => 150
          }
        )
      end

      it 'returns default transportation expert thresholds' do
        expect(safe_settings.transportation_expert_thresholds).to eq(
          {
            'stationary_max_speed' => 1,
            'running_vs_cycling_accel' => 0.25,
            'cycling_vs_driving_accel' => 0.4,
            'train_min_speed' => 80,
            'min_segment_duration' => 60,
            'time_gap_threshold' => 180,
            'min_flight_distance_km' => 100
          }
        )
      end

      it 'returns false for transportation expert mode' do
        expect(safe_settings.transportation_expert_mode?).to be false
      end
    end

    context 'with custom values' do
      let(:settings) do
        {
          'transportation_thresholds' => {
            'walking_max_speed' => 8,
            'cycling_max_speed' => 50,
            'driving_max_speed' => 200,
            'flying_min_speed' => 180
          },
          'transportation_expert_thresholds' => {
            'stationary_max_speed' => 2,
            'train_min_speed' => 100
          },
          'transportation_expert_mode' => true
        }
      end

      it 'returns custom transportation thresholds' do
        expect(safe_settings.transportation_thresholds).to eq(
          {
            'walking_max_speed' => 8,
            'cycling_max_speed' => 50,
            'driving_max_speed' => 200,
            'flying_min_speed' => 180
          }
        )
      end

      it 'returns custom transportation expert thresholds merged with defaults' do
        expect(safe_settings.transportation_expert_thresholds).to eq(
          {
            'stationary_max_speed' => 2,
            'running_vs_cycling_accel' => 0.25,
            'cycling_vs_driving_accel' => 0.4,
            'train_min_speed' => 100,
            'min_segment_duration' => 60,
            'time_gap_threshold' => 180,
            'min_flight_distance_km' => 100
          }
        )
      end

      it 'returns true for transportation expert mode' do
        expect(safe_settings.transportation_expert_mode?).to be true
      end
    end
  end

  describe '#enabled_transportation_modes' do
    let(:safe_settings) { described_class.new(settings) }
    let(:canonical) { Track::TRANSPORTATION_MODES.keys.map(&:to_s) }

    context 'when settings hash is empty' do
      let(:settings) { {} }

      it 'returns the canonical list of transportation modes' do
        expect(safe_settings.enabled_transportation_modes).to eq(canonical)
      end
    end

    context 'when value is nil' do
      let(:settings) { { 'enabled_transportation_modes' => nil } }

      it 'returns the canonical list of transportation modes' do
        expect(safe_settings.enabled_transportation_modes).to eq(canonical)
      end
    end

    context 'when value is an empty array' do
      let(:settings) { { 'enabled_transportation_modes' => [] } }

      it 'returns the canonical list of transportation modes' do
        expect(safe_settings.enabled_transportation_modes).to eq(canonical)
      end
    end

    context 'when value is a valid subset' do
      let(:settings) { { 'enabled_transportation_modes' => %w[walking cycling driving] } }

      it 'returns the subset' do
        expect(safe_settings.enabled_transportation_modes).to eq(%w[walking cycling driving])
      end
    end

    context 'when value contains a mix of valid and bogus modes' do
      let(:settings) { { 'enabled_transportation_modes' => %w[walking teleporting cycling jetpack] } }

      it 'filters out the bogus values' do
        expect(safe_settings.enabled_transportation_modes).to eq(%w[walking cycling])
      end
    end

    context 'when value contains only bogus modes' do
      let(:settings) { { 'enabled_transportation_modes' => %w[teleporting jetpack] } }

      it 'falls back to the canonical list' do
        expect(safe_settings.enabled_transportation_modes).to eq(canonical)
      end
    end
  end

  describe '#gps_filtering_enabled?' do
    it 'defaults to true when unset' do
      expect(described_class.new({}).gps_filtering_enabled?).to be true
    end

    it 'returns false when explicitly disabled' do
      expect(described_class.new({ 'gps_filtering_enabled' => false }).gps_filtering_enabled?).to be false
    end

    it 'casts string "false"' do
      expect(described_class.new({ 'gps_filtering_enabled' => 'false' }).gps_filtering_enabled?).to be false
    end
  end

  describe '#gps_accuracy_threshold' do
    it 'defaults to 100' do
      expect(described_class.new({}).gps_accuracy_threshold).to eq(100)
    end

    it 'returns the user-provided integer' do
      expect(described_class.new({ 'gps_accuracy_threshold' => 250 }).gps_accuracy_threshold).to eq(250)
    end

    it 'clamps below the minimum' do
      expect(described_class.new({ 'gps_accuracy_threshold' => 10 }).gps_accuracy_threshold).to eq(50)
    end

    it 'clamps above the maximum' do
      expect(described_class.new({ 'gps_accuracy_threshold' => 99_999 }).gps_accuracy_threshold).to eq(1000)
    end

    it 'coerces string values' do
      expect(described_class.new({ 'gps_accuracy_threshold' => '300' }).gps_accuracy_threshold).to eq(300)
    end
  end

  describe '#visit_radius_meters' do
    it 'returns 50 when missing' do
      expect(described_class.new({}).visit_radius_meters).to eq(100)
    end

    it 'clamps below the minimum to 5' do
      expect(described_class.new({ 'visit_radius_meters' => 1 }).visit_radius_meters).to eq(5)
    end

    it 'clamps above the maximum to 500' do
      expect(described_class.new({ 'visit_radius_meters' => 9999 }).visit_radius_meters).to eq(500)
    end

    it 'returns the user value within range' do
      expect(described_class.new({ 'visit_radius_meters' => 75 }).visit_radius_meters).to eq(75)
    end
  end

  describe '#visit_min_points' do
    it 'returns 3 when missing' do
      expect(described_class.new({}).visit_min_points).to eq(3)
    end

    it 'clamps below the minimum to 2' do
      expect(described_class.new({ 'visit_min_points' => 1 }).visit_min_points).to eq(2)
    end

    it 'clamps above the maximum to 20' do
      expect(described_class.new({ 'visit_min_points' => 99 }).visit_min_points).to eq(20)
    end

    it 'returns the user value within range' do
      expect(described_class.new({ 'visit_min_points' => 4 }).visit_min_points).to eq(4)
    end
  end

  describe '#stay_max_gap_minutes' do
    it 'returns 60 when missing' do
      expect(described_class.new({}).stay_max_gap_minutes).to eq(60)
    end

    it 'clamps below the minimum to 5' do
      expect(described_class.new({ 'stay_max_gap_minutes' => 1 }).stay_max_gap_minutes).to eq(5)
    end

    it 'clamps above the maximum to 720' do
      expect(described_class.new({ 'stay_max_gap_minutes' => 1000 }).stay_max_gap_minutes).to eq(720)
    end

    it 'returns the user value within range' do
      expect(described_class.new({ 'stay_max_gap_minutes' => 90 }).stay_max_gap_minutes).to eq(90)
    end

    it 'is included in #config' do
      expect(described_class.new({}).config).to include(stay_max_gap_minutes: 60)
    end
  end

  describe '#visit_density_fill_enabled?' do
    it 'returns true when missing' do
      expect(described_class.new({}).visit_density_fill_enabled?).to be true
    end

    it 'returns false for "0"' do
      expect(described_class.new({ 'visit_density_fill_enabled' => '0' }).visit_density_fill_enabled?).to be false
    end

    it 'returns true for "1"' do
      expect(described_class.new({ 'visit_density_fill_enabled' => '1' }).visit_density_fill_enabled?).to be true
    end

    it 'returns false for false' do
      expect(described_class.new({ 'visit_density_fill_enabled' => false }).visit_density_fill_enabled?).to be false
    end
  end
  describe '#fog_of_war_mode' do
    it 'defaults to points' do
      expect(described_class.new.fog_of_war_mode).to eq('points')
    end

    it 'returns hexagons when set' do
      expect(described_class.new({ 'fog_of_war_mode' => 'hexagons' }).fog_of_war_mode).to eq('hexagons')
    end

    it 'falls back to points for invalid values' do
      expect(described_class.new({ 'fog_of_war_mode' => 'octagons' }).fog_of_war_mode).to eq('points')
    end

    it 'is included in config' do
      expect(described_class.new.config[:fog_of_war_mode]).to eq('points')
    end
  end

  describe '#maps_maplibre_custom_theme' do
    let(:noir_tokens) do
      {
        'bg' => '#000000', 'water' => '#0A0A0A', 'parks' => '#111111',
        'buildings' => '#141414', 'railway' => '#808080', 'boundaries' => '#4D4D4D',
        'road_motorway' => '#FFFFFF', 'road_primary' => '#E0E0E0',
        'road_secondary' => '#B0B0B0', 'road_tertiary' => '#808080',
        'road_residential' => '#505050', 'road_default' => '#808080'
      }
    end

    it 'defaults to the noir preset' do
      expect(described_class.new.maps_maplibre_custom_theme).to eq(
        'base' => 'noir', 'tokens' => noir_tokens
      )
    end

    it 'returns stored base and tokens' do
      settings = {
        'maps_maplibre_custom_theme' => {
          'base' => 'blueprint',
          'tokens' => noir_tokens.merge('bg' => '#1E3A5F')
        }
      }

      theme = described_class.new(settings).maps_maplibre_custom_theme

      expect(theme['base']).to eq('blueprint')
      expect(theme['tokens']['bg']).to eq('#1E3A5F')
    end

    it 'resolves every token when a stored hash is partial' do
      settings = {
        'maps_maplibre_custom_theme' => { 'tokens' => { 'bg' => '#123456' } }
      }

      theme = described_class.new(settings).maps_maplibre_custom_theme

      expect(theme['tokens']['bg']).to eq('#123456')
      expect(theme['tokens']['water']).to eq('#0A0A0A')
      expect(theme['base']).to eq('noir')
    end

    it 'is included in config' do
      expect(described_class.new.config[:maps_maplibre_custom_theme]['base']).to eq('noir')
    end
  end

  describe '#maps_maplibre_tiles_url' do
    it 'defaults to nil (built-in tiles)' do
      expect(described_class.new.maps_maplibre_tiles_url).to be_nil
    end

    it 'returns the stored URL' do
      settings = described_class.new(
        { 'maps_maplibre_tiles_url' => 'https://tiles.example.com/{z}/{x}/{y}.mvt' }
      )

      expect(settings.maps_maplibre_tiles_url).to eq('https://tiles.example.com/{z}/{x}/{y}.mvt')
    end

    it 'is included in config' do
      expect(described_class.new.config).to have_key(:maps_maplibre_tiles_url)
    end
  end

  describe 'layer colors' do
    it 'defaults route_color to v1 blue' do
      expect(described_class.new.route_color).to eq('#0000ff')
    end

    it 'defaults track_color to the serializer default' do
      expect(described_class.new.track_color).to eq('#6366F1')
    end

    it 'returns stored values' do
      settings = described_class.new({ 'route_color' => '#ff0000', 'track_color' => '#00ff00' })

      expect(settings.route_color).to eq('#ff0000')
      expect(settings.track_color).to eq('#00ff00')
    end

    it 'is included in config' do
      config = described_class.new.config

      expect(config[:route_color]).to eq('#0000ff')
      expect(config[:track_color]).to eq('#6366F1')
    end
  end
end
