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
            immich_url: nil,
            immich_api_key: nil,
            photoprism_url: nil,
            photoprism_api_key: nil,
            maps: { 'distance_unit' => 'km' },
            distance_unit: 'km',
            visits_suggestions_enabled: true,
            speed_color_scale: nil,
            fog_of_war_threshold: 50,
            enabled_map_layers: %w[Tracks Heatmap],
            maps_maplibre_style: 'light',
            globe_projection: false,
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
            timezone: 'UTC'
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
            'immich_skip_ssl_verification' => false,
            'photoprism_url' => 'https://photoprism.example.com',
            'photoprism_api_key' => 'photoprism-key',
            'photoprism_skip_ssl_verification' => false,
            'maps' => { 'distance_unit' => 'km', 'name' => 'custom', 'url' => 'https://custom.example.com' },
            'visits_suggestions_enabled' => false,
            'enabled_map_layers' => %w[Points Routes Areas Photos],
            'maps_maplibre_style' => 'light',
            'news_emails_enabled' => true,
            'globe_projection' => false,
            'supporter_email' => nil,
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
            'timezone' => 'UTC'
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
            immich_url: 'https://immich.example.com',
            immich_api_key: 'immich-key',
            photoprism_url: 'https://photoprism.example.com',
            photoprism_api_key: 'photoprism-key',
            maps: { 'distance_unit' => 'km', 'name' => 'custom', 'url' => 'https://custom.example.com' },
            distance_unit: 'km',
            visits_suggestions_enabled: false,
            speed_color_scale: nil,
            fog_of_war_threshold: 50,
            enabled_map_layers: %w[Points Routes Areas Photos],
            maps_maplibre_style: 'light',
            globe_projection: false,
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
            timezone: 'UTC'
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
end
