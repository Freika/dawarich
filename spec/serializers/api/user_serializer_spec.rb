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

    context 'subscription data' do
      context 'when not self-hosted (hosted instance)' do
        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        end

        it 'includes subscription data' do
          expect(serializer).to have_key(:subscription)
          expect(serializer[:subscription]).to include(:status, :active_until)
        end

        it 'returns correct subscription values' do
          subscription = serializer[:subscription]
          expect(subscription[:status]).to eq(user.status)
          expect(subscription[:active_until]).to eq(user.active_until)
        end

        context 'with specific subscription values' do
          it 'serializes trial user status correctly' do
            # When not self-hosted, users start with trial status via start_trial callback
            test_user = create(:user)
            serializer_result = described_class.new(test_user).call
            subscription = serializer_result[:subscription]

            expect(subscription[:status]).to eq('trial')
            expect(subscription[:active_until]).to be_within(1.second).of(7.days.from_now)
          end

          it 'serializes subscription data with all expected fields' do
            test_user = create(:user)
            serializer_result = described_class.new(test_user).call
            subscription = serializer_result[:subscription]

            expect(subscription).to include(:status, :active_until)
            expect(subscription[:status]).to be_a(String)
            expect(subscription[:active_until]).to be_a(ActiveSupport::TimeWithZone)
          end
        end
      end

      context 'when self-hosted' do
        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        end

        it 'does not include subscription data' do
          expect(serializer).not_to have_key(:subscription)
        end

        it 'still includes user and settings data' do
          expect(serializer).to have_key(:user)
          expect(serializer[:user]).to include(:email, :theme, :settings)
        end
      end
    end
  end
end
