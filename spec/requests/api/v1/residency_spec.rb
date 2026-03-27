# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Residency', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  describe 'GET /api/v1/residency' do
    context 'without authentication' do
      it 'returns 401' do
        get '/api/v1/residency'

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is on Lite plan (cloud)' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :lite)
      end

      it 'returns 403' do
        get '/api/v1/residency', headers: headers

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body['error']).to eq('pro_plan_required')
      end
    end

    context 'with authentication' do
      before do
        create(:stat, user:, year: 2025, month: 1)
        create(:stat, user:, year: 2025, month: 2)

        # 3 days in Germany
        (1..3).each do |day|
          create(:point,
                 user:,
                 country_name: 'Germany',
                 timestamp: Time.zone.local(2025, 1, day, 12, 0).to_i)
        end

        # 2 days in France
        (10..11).each do |day|
          create(:point,
                 user:,
                 country_name: 'France',
                 timestamp: Time.zone.local(2025, 1, day, 12, 0).to_i)
        end
      end

      it 'returns residency data for the requested year' do
        get '/api/v1/residency', params: { year: 2025 }, headers: headers

        expect(response).to have_http_status(:ok)

        json = response.parsed_body
        expect(json['year']).to eq(2025)
        expect(json['counting_mode']).to eq('any_presence')
        expect(json['total_tracked_days']).to eq(5)
        expect(json['countries'].size).to eq(2)
      end

      it 'returns countries sorted by days descending' do
        get '/api/v1/residency', params: { year: 2025 }, headers: headers

        json = response.parsed_body
        countries = json['countries']
        expect(countries.first['country_name']).to eq('Germany')
        expect(countries.first['days']).to eq(3)
        expect(countries.last['country_name']).to eq('France')
        expect(countries.last['days']).to eq(2)
      end

      it 'includes periods for each country' do
        get '/api/v1/residency', params: { year: 2025 }, headers: headers

        json = response.parsed_body
        germany = json['countries'].find { |c| c['country_name'] == 'Germany' }

        expect(germany['periods']).to be_an(Array)
        expect(germany['periods'].first['start_date']).to eq('2025-01-01')
        expect(germany['periods'].first['end_date']).to eq('2025-01-03')
        expect(germany['periods'].first['consecutive_days']).to eq(3)
      end

      it 'includes available_years' do
        get '/api/v1/residency', params: { year: 2025 }, headers: headers

        json = response.parsed_body
        expect(json['available_years']).to include(2025)
      end

      it 'defaults to most recent year when no year param' do
        get '/api/v1/residency', headers: headers

        expect(response).to have_http_status(:ok)

        json = response.parsed_body
        expect(json['year']).to eq(2025)
      end

      context 'when year has no data' do
        it 'returns empty countries' do
          get '/api/v1/residency', params: { year: 2020 }, headers: headers

          json = response.parsed_body
          expect(json['countries']).to eq([])
          expect(json['total_tracked_days']).to eq(0)
        end
      end
    end
  end
end
