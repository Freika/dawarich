# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Timeline', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }
  let(:auth_headers) { { 'Authorization' => "Bearer #{api_key}" } }
  let(:place) { create(:place, name: 'Home') }

  describe 'GET /api/v1/timeline' do
    let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

    let!(:visit) do
      create(:visit,
             user: user,
             place: place,
             name: 'Home',
             started_at: day + 10.hours,
             ended_at: day + 12.hours,
             duration: 7200)
    end

    let!(:track) do
      create(:track,
             user: user,
             start_at: day + 12.hours,
             end_at: day + 13.hours,
             distance: 5000,
             duration: 3600,
             dominant_mode: :walking)
    end

    let(:params) do
      {
        start_at: day.iso8601,
        end_at: (day + 1.day).iso8601
      }
    end

    context 'with valid authentication' do
      it 'returns correct JSON structure' do
        get '/api/v1/timeline', params: params, headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to have_key('days')
        expect(json['days'].length).to eq(1)

        day_data = json['days'].first
        expect(day_data['date']).to eq('2025-01-15')
        expect(day_data).to have_key('summary')
        expect(day_data).to have_key('entries')
        expect(day_data).to have_key('bounds')
      end

      it 'returns interleaved entries' do
        get '/api/v1/timeline', params: params, headers: auth_headers

        json = JSON.parse(response.body)
        entries = json['days'].first['entries']
        expect(entries.length).to eq(2)
        expect(entries[0]['type']).to eq('visit')
        expect(entries[1]['type']).to eq('journey')
      end

      it 'respects date range params' do
        get '/api/v1/timeline', params: {
          start_at: (day - 10.days).iso8601,
          end_at: (day - 9.days).iso8601
        }, headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['days']).to be_empty
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get '/api/v1/timeline', params: params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'only returns data for the authenticated user' do
      let(:other_user) { create(:user) }

      let!(:other_visit) do
        create(:visit,
               user: other_user,
               place: place,
               name: 'Other Home',
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 7200)
      end

      it 'excludes other users data' do
        get '/api/v1/timeline', params: params, headers: auth_headers

        json = JSON.parse(response.body)
        names = json['days'].flat_map { |d| d['entries'].map { |e| e['name'] } }.compact
        expect(names).to include('Home')
        expect(names).not_to include('Other Home')
      end
    end
  end
end
