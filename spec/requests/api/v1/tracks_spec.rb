# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/api/v1/tracks', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  describe 'GET /index' do
    let!(:track1) do
      create(:track, user: user,
             start_at: Time.zone.parse('2024-01-01 10:00'),
             end_at: Time.zone.parse('2024-01-01 12:00'))
    end
    let!(:track2) do
      create(:track, user: user,
             start_at: Time.zone.parse('2024-01-02 10:00'),
             end_at: Time.zone.parse('2024-01-02 12:00'))
    end
    let!(:other_user_track) { create(:track) } # Different user

    it 'returns successful response' do
      get api_v1_tracks_url, headers: headers
      expect(response).to be_successful
    end

    it 'returns GeoJSON FeatureCollection format' do
      get api_v1_tracks_url, headers: headers
      json = JSON.parse(response.body)

      expect(json['type']).to eq('FeatureCollection')
      expect(json['features']).to be_an(Array)
    end

    it 'returns only current user tracks' do
      get api_v1_tracks_url, headers: headers
      json = JSON.parse(response.body)

      expect(json['features'].length).to eq(2)
      track_ids = json['features'].map { |f| f['properties']['id'] }
      expect(track_ids).to contain_exactly(track1.id, track2.id)
      expect(track_ids).not_to include(other_user_track.id)
    end

    it 'includes default color in feature properties' do
      get api_v1_tracks_url, headers: headers
      json = JSON.parse(response.body)

      json['features'].each do |feature|
        expect(feature['properties']['color']).to eq('#6366F1')
      end
    end

    it 'includes GeoJSON geometry' do
      get api_v1_tracks_url, headers: headers
      json = JSON.parse(response.body)

      json['features'].each do |feature|
        expect(feature['geometry']).to be_present
        expect(feature['geometry']['type']).to eq('LineString')
        expect(feature['geometry']['coordinates']).to be_an(Array)
      end
    end

    it 'includes track metadata in properties' do
      get api_v1_tracks_url, headers: headers
      json = JSON.parse(response.body)

      feature = json['features'].first
      expect(feature['properties']).to include(
        'id', 'color', 'start_at', 'end_at', 'distance', 'avg_speed', 'duration'
      )
    end

    it 'sets pagination headers' do
      get api_v1_tracks_url, headers: headers

      expect(response.headers['X-Current-Page']).to be_present
      expect(response.headers['X-Total-Pages']).to be_present
      expect(response.headers['X-Total-Count']).to be_present
    end

    context 'with pagination parameters' do
      before do
        create_list(:track, 5, user: user)
      end

      it 'respects per_page parameter' do
        get api_v1_tracks_url, params: { per_page: 2 }, headers: headers
        json = JSON.parse(response.body)

        expect(json['features'].length).to eq(2)
        expect(response.headers['X-Total-Pages'].to_i).to be > 1
      end

      it 'respects page parameter' do
        get api_v1_tracks_url, params: { page: 2, per_page: 2 }, headers: headers

        expect(response.headers['X-Current-Page']).to eq('2')
      end
    end

    context 'with date range filtering' do
      it 'returns tracks that overlap with date range' do
        get api_v1_tracks_url, params: {
          start_at: '2024-01-01T00:00:00',
          end_at: '2024-01-01T23:59:59'
        }, headers: headers

        json = JSON.parse(response.body)
        expect(json['features'].length).to eq(1)
        expect(json['features'].first['properties']['id']).to eq(track1.id)
      end

      it 'includes tracks that start before and end after range' do
        long_track = create(:track, user: user,
                            start_at: Time.zone.parse('2024-01-01 08:00'),
                            end_at: Time.zone.parse('2024-01-03 20:00'))

        get api_v1_tracks_url, params: {
          start_at: '2024-01-02T00:00:00',
          end_at: '2024-01-02T23:59:59'
        }, headers: headers

        json = JSON.parse(response.body)
        track_ids = json['features'].map { |f| f['properties']['id'] }
        expect(track_ids).to include(long_track.id, track2.id)
      end

      it 'excludes tracks outside date range' do
        get api_v1_tracks_url, params: {
          start_at: '2024-01-05T00:00:00',
          end_at: '2024-01-05T23:59:59'
        }, headers: headers

        json = JSON.parse(response.body)
        expect(json['features']).to be_empty
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get api_v1_tracks_url
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user has no tracks' do
      let(:user_without_tracks) { create(:user) }

      it 'returns empty FeatureCollection' do
        get api_v1_tracks_url, headers: { 'Authorization' => "Bearer #{user_without_tracks.api_key}" }
        json = JSON.parse(response.body)

        expect(json['type']).to eq('FeatureCollection')
        expect(json['features']).to eq([])
      end
    end
  end

  describe 'GET /show' do
    let!(:track) do
      create(:track, user: user,
             start_at: Time.zone.parse('2024-01-01 10:00'),
             end_at: Time.zone.parse('2024-01-01 11:00'),
             distance: 5000.0,
             avg_speed: 30.5,
             duration: 3600)
    end
    let!(:segment1) do
      create(:track_segment, :walking, track: track,
             start_index: 0, end_index: 5, distance: 2000, duration: 1800)
    end
    let!(:segment2) do
      create(:track_segment, track: track,
             start_index: 6, end_index: 10, distance: 3000, duration: 1800)
    end

    it 'returns successful response with GeoJSON FeatureCollection' do
      get api_v1_track_url(track), headers: headers
      expect(response).to be_successful

      json = JSON.parse(response.body)
      expect(json['type']).to eq('FeatureCollection')
      expect(json['features'].length).to eq(1)
    end

    it 'returns track properties' do
      get api_v1_track_url(track), headers: headers
      json = JSON.parse(response.body)

      properties = json['features'].first['properties']
      expect(properties['id']).to eq(track.id)
      expect(properties['color']).to eq('#6366F1')
      expect(properties['start_at']).to eq(track.start_at.utc.iso8601)
      expect(properties['end_at']).to eq(track.end_at.utc.iso8601)
      expect(properties['distance']).to eq(5000)
      expect(properties['avg_speed']).to eq(30.5)
      expect(properties['duration']).to eq(3600)
    end

    it 'includes segments with transportation mode data' do
      get api_v1_track_url(track), headers: headers
      json = JSON.parse(response.body)

      segments = json['features'].first['properties']['segments']
      expect(segments.length).to eq(2)

      first_segment = segments.first
      expect(first_segment['mode']).to eq('walking')
      expect(first_segment['emoji']).to be_present
      expect(first_segment['color']).to be_present
      expect(first_segment['start_index']).to eq(0)
      expect(first_segment['end_index']).to eq(5)
    end

    it 'returns not found for another user track' do
      other_user = create(:user)
      other_track = create(:track, user: other_user)

      get api_v1_track_url(other_track), headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns not found for non-existent track' do
      get api_v1_track_url(id: -1), headers: headers
      expect(response).to have_http_status(:not_found)
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get api_v1_track_url(track)
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
