# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trial::Upgrades', type: :request do
  describe 'GET /trial/upgrade' do
    let(:user) { create(:user) }

    before do
      stub_const('MANAGER_URL', 'https://manager.example.test')
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    context 'when not signed in' do
      it 'redirects to login' do
        get '/trial/upgrade', params: { plan: 'pro', interval: 'annual' }

        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('sign_in')
      end
    end

    # The navbar Expired button now goes through this action, so a lapsed
    # account must still reach checkout instead of a gate.
    [[:trial, { active_until: 1.day.ago }], [:inactive, {}]].each do |trait, attrs|
      context "when signed in as a #{trait} user #{attrs.any? ? 'whose trial expired' : ''}".strip do
        it 'redirects to Manager checkout with a token' do
          sign_in create(:user, trait, **attrs)

          get '/trial/upgrade'

          expect(response).to redirect_to(%r{\Ahttps://manager\.example\.test/auth/dawarich\?token=})
        end
      end
    end

    context 'when signed in' do
      before { sign_in(user) }

      it 'redirects to Manager with a JWT containing plan and interval' do
        get '/trial/upgrade', params: { plan: 'pro', interval: 'annual' }

        expect(response).to redirect_to(%r{\Ahttps://manager\.example\.test/auth/dawarich\?token=})

        token = Rack::Utils.parse_query(URI(response.location).query)['token']
        payload = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, { algorithm: 'HS256' }).first

        expect(payload['plan']).to eq('pro')
        expect(payload['interval']).to eq('annual')
        expect(payload['user_id']).to eq(user.id)
      end

      it 'sanitizes unknown plan values to nil' do
        get '/trial/upgrade', params: { plan: 'enterprise', interval: 'annual' }

        token = Rack::Utils.parse_query(URI(response.location).query)['token']
        payload = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, { algorithm: 'HS256' }).first

        expect(payload).not_to have_key('plan')
        expect(payload['interval']).to eq('annual')
      end

      it 'sanitizes unknown interval values to nil' do
        get '/trial/upgrade', params: { plan: 'pro', interval: 'weekly' }

        token = Rack::Utils.parse_query(URI(response.location).query)['token']
        payload = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, { algorithm: 'HS256' }).first

        expect(payload['plan']).to eq('pro')
        expect(payload).not_to have_key('interval')
      end

      it 'accepts lite and monthly as valid' do
        get '/trial/upgrade', params: { plan: 'lite', interval: 'monthly' }

        token = Rack::Utils.parse_query(URI(response.location).query)['token']
        payload = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, { algorithm: 'HS256' }).first

        expect(payload['plan']).to eq('lite')
        expect(payload['interval']).to eq('monthly')
      end

      it 'accepts the family plan' do
        get '/trial/upgrade', params: { plan: 'family', interval: 'annual' }

        token = Rack::Utils.parse_query(URI(response.location).query)['token']
        payload = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, { algorithm: 'HS256' }).first

        expect(payload['plan']).to eq('family')
      end

      it 'forwards UTM parameters to Manager and drops anything else' do
        get '/trial/upgrade', params: { utm_source: 'app', utm_medium: 'badge', utm_campaign: 'lite_upgrade',
                                        utm_content: 'pro_badge', evil: 'x' }

        query = Rack::Utils.parse_query(URI(response.location).query)
        expect(query.keys).to contain_exactly('token', 'utm_source', 'utm_medium', 'utm_campaign', 'utm_content')
        expect(query['utm_content']).to eq('pro_badge')
      end

      describe 'analytics telemetry' do
        def capture_telemetry
          captured = []
          allow(Rails.logger).to receive(:info).and_wrap_original do |original, *args, &block|
            payload = block ? block.call : args.first
            if payload.is_a?(String) && payload.start_with?('{') && payload.include?('trial_upgrades_viewed')
              captured << payload
            end
            original.call(*args, &block)
          end
          captured
        end

        it 'logs a structured trial_upgrades_viewed event with sanitized plan and interval' do
          captured = capture_telemetry

          get '/trial/upgrade', params: { plan: 'pro', interval: 'annual' }

          expect(captured).not_to be_empty
          json = JSON.parse(captured.first)
          expect(json['event']).to eq('trial_upgrades_viewed')
          expect(json['user_id']).to eq(user.id)
          expect(json['plan']).to eq('pro')
          expect(json['interval']).to eq('annual')
        end

        it 'logs nil plan and nil interval when params are unrecognised' do
          captured = capture_telemetry

          get '/trial/upgrade', params: { plan: 'evil', interval: 'hourly' }

          expect(captured).not_to be_empty
          json = JSON.parse(captured.first)
          expect(json['event']).to eq('trial_upgrades_viewed')
          expect(json['user_id']).to eq(user.id)
          expect(json).to have_key('plan')
          expect(json['plan']).to be_nil
          expect(json).to have_key('interval')
          expect(json['interval']).to be_nil
        end
      end
    end
  end
end
