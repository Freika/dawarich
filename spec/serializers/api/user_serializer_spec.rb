# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::UserSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(user).call }

    let(:user) { create(:user) }

    it 'returns JSON with correct user attributes' do
      expect(serializer[:user][:email]).to eq(user.email)
      expect(serializer[:user][:theme]).to eq(user.theme)
      expect(serializer[:user][:created_at]).to eq(user.created_at)
      expect(serializer[:user][:updated_at]).to eq(user.updated_at)
    end

    it 'returns settings with expected keys and types' do
      settings = serializer[:user][:settings]
      expect(settings).to include(
        :maps,
        :fog_of_war_meters,
        :meters_between_routes,
        :preferred_map_layer,
        :speed_colored_routes,
        :points_rendering_mode,
        :minutes_between_routes,
        :time_threshold_minutes,
        :merge_threshold_minutes,
        :live_map_enabled,
        :route_opacity,
        :immich_url,
        :photoprism_url,
        :visits_suggestions_enabled,
        :speed_color_scale,
        :fog_of_war_threshold
      )
    end

    context 'with custom settings' do
      let(:custom_settings) do
        {
          'fog_of_war_meters' => 123,
          'meters_between_routes' => 456,
          'preferred_map_layer' => 'Satellite',
          'speed_colored_routes' => true,
          'points_rendering_mode' => 'cluster',
          'minutes_between_routes' => 42,
          'time_threshold_minutes' => 99,
          'merge_threshold_minutes' => 77,
          'live_map_enabled' => false,
          'route_opacity' => 0.75,
          'immich_url' => 'https://immich.example.com',
          'photoprism_url' => 'https://photoprism.example.com',
          'visits_suggestions_enabled' => 'false',
          'speed_color_scale' => 'rainbow',
          'fog_of_war_threshold' => 5,
          'maps' => { 'distance_unit' => 'mi' }
        }
      end

      let(:user) { create(:user, settings: custom_settings) }

      it 'serializes custom settings correctly' do
        settings = serializer[:user][:settings]
        expect(settings[:fog_of_war_meters]).to eq(123)
        expect(settings[:meters_between_routes]).to eq(456)
        expect(settings[:preferred_map_layer]).to eq('Satellite')
        expect(settings[:speed_colored_routes]).to eq(true)
        expect(settings[:points_rendering_mode]).to eq('cluster')
        expect(settings[:minutes_between_routes]).to eq(42)
        expect(settings[:time_threshold_minutes]).to eq(99)
        expect(settings[:merge_threshold_minutes]).to eq(77)
        expect(settings[:live_map_enabled]).to eq(false)
        expect(settings[:route_opacity]).to eq(0.75)
        expect(settings[:immich_url]).to eq('https://immich.example.com')
        expect(settings[:photoprism_url]).to eq('https://photoprism.example.com')
        expect(settings[:visits_suggestions_enabled]).to eq(false)
        expect(settings[:speed_color_scale]).to eq('rainbow')
        expect(settings[:fog_of_war_threshold]).to eq(5)
        expect(settings[:maps]).to eq({ 'distance_unit' => 'mi' })
      end
    end
  end
end
