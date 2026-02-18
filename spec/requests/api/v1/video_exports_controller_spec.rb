# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::VideoExportsController do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }
  let(:headers) { { 'Authorization' => "Bearer #{api_key}" } }

  describe 'POST /api/v1/video_exports' do
    let(:params) do
      {
        start_at: 1.day.ago.iso8601,
        end_at: Time.current.iso8601,
        config: {
          orientation: 'landscape',
          speed_multiplier: 10,
          map_style: 'dark',
          map_behavior: 'north_up',
          overlays: { time: true, speed: true, distance: true, track_name: true }
        }
      }
    end

    it 'creates a video export and enqueues a job' do
      expect do
        post '/api/v1/video_exports', params: params, headers: headers, as: :json
      end.to change(VideoExport, :count).by(1)
        .and have_enqueued_job(VideoExportJob)

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json['id']).to be_present
      expect(json['status']).to eq('created')
    end

    context 'with a track_id' do
      let(:track) { create(:track, user: user) }

      it 'creates a video export for a specific track' do
        post '/api/v1/video_exports',
             params: params.merge(track_id: track.id),
             headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(response.parsed_body['track_id']).to eq(track.id)
      end
    end

    context 'with missing required params' do
      it 'returns bad request when start_at is missing' do
        post '/api/v1/video_exports',
             params: params.except(:start_at),
             headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post '/api/v1/video_exports', params: params, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/video_exports' do
    before do
      create_list(:video_export, 3, user: user)
      create(:video_export) # another user's export
    end

    it 'returns only current user video exports' do
      get '/api/v1/video_exports', headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.length).to eq(3)
    end
  end

  describe 'GET /api/v1/video_exports/:id' do
    let(:video_export) { create(:video_export, user: user) }

    it 'returns the video export' do
      get "/api/v1/video_exports/#{video_export.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['id']).to eq(video_export.id)
      expect(json['status']).to eq('created')
    end

    it 'returns not found for another user export' do
      other_export = create(:video_export)

      get "/api/v1/video_exports/#{other_export.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/video_exports/:id' do
    let!(:video_export) { create(:video_export, user: user) }

    it 'deletes the video export' do
      expect do
        delete "/api/v1/video_exports/#{video_export.id}", headers: headers
      end.to change(VideoExport, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe 'POST /api/v1/video_exports/:id/callback' do
    let(:video_export) { create(:video_export, :processing, user: user) }
    let(:token) { VideoExports::CallbackToken.generate(video_export.id) }

    context 'with a successful render' do
      let(:video_file) do
        Rack::Test::UploadedFile.new(
          StringIO.new('fake mp4 content'),
          'video/mp4',
          true,
          original_filename: 'route_replay.mp4'
        )
      end

      it 'attaches the video file and marks as completed' do
        post "/api/v1/video_exports/#{video_export.id}/callback",
             params: { token: token, status: 'completed', file: video_file }

        expect(response).to have_http_status(:ok)
        video_export.reload
        expect(video_export).to be_completed
        expect(video_export.file).to be_attached
      end

      it 'creates a notification for the user' do
        expect do
          post "/api/v1/video_exports/#{video_export.id}/callback",
               params: { token: token, status: 'completed', file: video_file }
        end.to change(Notification, :count).by(1)

        notification = user.notifications.last
        expect(notification.title).to include('Video export')
        expect(notification).to be_info
      end
    end

    context 'with a failed render' do
      it 'marks as failed and stores error message' do
        post "/api/v1/video_exports/#{video_export.id}/callback",
             params: { token: token, status: 'failed', error_message: 'Render timeout' }

        expect(response).to have_http_status(:ok)
        video_export.reload
        expect(video_export).to be_failed
        expect(video_export.error_message).to eq('Render timeout')
      end

      it 'creates an error notification' do
        expect do
          post "/api/v1/video_exports/#{video_export.id}/callback",
               params: { token: token, status: 'failed', error_message: 'Render timeout' }
        end.to change(Notification, :count).by(1)

        notification = user.notifications.last
        expect(notification).to be_error
      end
    end

    context 'with an invalid token' do
      it 'returns unauthorized' do
        post "/api/v1/video_exports/#{video_export.id}/callback",
             params: { token: 'invalid', status: 'completed' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
