# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trial::Upgrades', type: :request do
  describe 'GET /trial/upgrade' do
    let(:user) { create(:user) }

    before do
      stub_const('MANAGER_URL', 'https://manager.example.test')
    end

    context 'when not signed in' do
      it 'redirects to login' do
        get '/trial/upgrade', params: { plan: 'pro', interval: 'annual' }

        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('sign_in')
      end
    end

    context 'when signed in' do
      before { sign_in(user) }

      it 'redirects to Manager with a JWT containing plan and interval' do
        get '/trial/upgrade', params: { plan: 'pro', interval: 'annual' }

        expect(response).to redirect_to(%r{\Ahttps://manager\.example\.test/auth/dawarich\?token=})

        token = CGI.parse(URI(response.location).query)['token'].first
        payload = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, { algorithm: 'HS256' }).first

        expect(payload['plan']).to eq('pro')
        expect(payload['interval']).to eq('annual')
        expect(payload['user_id']).to eq(user.id)
      end

      it 'sanitizes unknown plan values to nil' do
        get '/trial/upgrade', params: { plan: 'enterprise', interval: 'annual' }

        token = CGI.parse(URI(response.location).query)['token'].first
        payload = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, { algorithm: 'HS256' }).first

        expect(payload).not_to have_key('plan')
        expect(payload['interval']).to eq('annual')
      end

      it 'sanitizes unknown interval values to nil' do
        get '/trial/upgrade', params: { plan: 'pro', interval: 'weekly' }

        token = CGI.parse(URI(response.location).query)['token'].first
        payload = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, { algorithm: 'HS256' }).first

        expect(payload['plan']).to eq('pro')
        expect(payload).not_to have_key('interval')
      end

      it 'accepts lite and monthly as valid' do
        get '/trial/upgrade', params: { plan: 'lite', interval: 'monthly' }

        token = CGI.parse(URI(response.location).query)['token'].first
        payload = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, { algorithm: 'HS256' }).first

        expect(payload['plan']).to eq('lite')
        expect(payload['interval']).to eq('monthly')
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
