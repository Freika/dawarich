# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Video Export Flow', type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:api_key) { user.api_key }
  let(:headers) { { 'Authorization' => "Bearer #{api_key}" } }

  let(:video_service_url) { 'http://dawarich_video:3100' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('VIDEO_SERVICE_URL', anything).and_return(video_service_url)
    allow(ENV).to receive(:fetch).with('APPLICATION_HOST', anything).and_return('http://localhost:3000')
  end

  describe 'happy path: create → process → callback → download' do
    it 'completes the full video export pipeline' do
      # Stub the video service to accept the render request
      stub_request(:post, "#{video_service_url}/api/render")
        .to_return(status: 200, body: { id: 'render-123', status: 'queued' }.to_json)

      # Step 1: Create video export via API
      post '/api/v1/video_exports', params: {
        start_at: 1.day.ago.iso8601,
        end_at: Time.current.iso8601,
        config: {
          orientation: 'landscape',
          speed_multiplier: 10,
          map_style: 'dark',
          map_behavior: 'north_up',
          overlays: { time: true, speed: true, distance: true, track_name: true }
        }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      video_export = VideoExport.last
      expect(video_export).to be_created

      # Step 2: Process the job (this normally happens in background)
      perform_enqueued_jobs { VideoExportJob.perform_now(video_export.id) }

      video_export.reload
      expect(video_export).to be_processing

      # Verify the render request was sent
      expect(WebMock).to have_requested(:post, "#{video_service_url}/api/render")
        .with { |req| JSON.parse(req.body)['video_export_id'] == video_export.id }

      # Step 3: Simulate callback from video service
      token = VideoExports::CallbackToken.generate(video_export.id)
      video_file = Rack::Test::UploadedFile.new(
        StringIO.new('fake mp4 content'),
        'video/mp4',
        true,
        original_filename: 'route_replay.mp4'
      )

      post "/api/v1/video_exports/#{video_export.id}/callback",
           params: { token: token, status: 'completed', file: video_file }

      expect(response).to have_http_status(:ok)

      # Step 4: Verify final state
      video_export.reload
      expect(video_export).to be_completed
      expect(video_export.file).to be_attached

      # Step 5: Verify notification was created
      notification = user.notifications.last
      expect(notification.title).to include('Video export')
      expect(notification).to be_info

      # Step 6: Verify the export is visible in the list
      get '/api/v1/video_exports', headers: headers
      expect(response).to have_http_status(:ok)
      exports = response.parsed_body
      expect(exports.length).to eq(1)
      expect(exports.first['status']).to eq('completed')
      expect(exports.first['download_url']).to be_present
    end
  end

  describe 'error path: create → process → failure callback' do
    it 'handles render failures gracefully' do
      stub_request(:post, "#{video_service_url}/api/render")
        .to_return(status: 200, body: { id: 'render-456', status: 'queued' }.to_json)

      # Create video export
      post '/api/v1/video_exports', params: {
        start_at: 1.day.ago.iso8601,
        end_at: Time.current.iso8601,
        config: { orientation: 'landscape', speed_multiplier: 10, map_style: 'dark',
                  map_behavior: 'north_up', overlays: { time: true } }
      }, headers: headers, as: :json

      video_export = VideoExport.last

      # Process the job
      perform_enqueued_jobs { VideoExportJob.perform_now(video_export.id) }

      # Simulate error callback
      token = VideoExports::CallbackToken.generate(video_export.id)
      post "/api/v1/video_exports/#{video_export.id}/callback",
           params: { token: token, status: 'failed', error_message: 'Out of memory during render' }

      expect(response).to have_http_status(:ok)

      # Verify failure state
      video_export.reload
      expect(video_export).to be_failed
      expect(video_export.error_message).to eq('Out of memory during render')

      # Verify error notification
      notification = user.notifications.last
      expect(notification).to be_error
      expect(notification.content).to include('Out of memory')
    end
  end

  describe 'service unreachable' do
    it 'marks export as failed when video service is down' do
      stub_request(:post, "#{video_service_url}/api/render")
        .to_raise(Errno::ECONNREFUSED)

      post '/api/v1/video_exports', params: {
        start_at: 1.day.ago.iso8601,
        end_at: Time.current.iso8601,
        config: { orientation: 'landscape', speed_multiplier: 10, map_style: 'dark',
                  map_behavior: 'north_up', overlays: {} }
      }, headers: headers, as: :json

      video_export = VideoExport.last

      # Job should catch the error and mark as failed
      perform_enqueued_jobs { VideoExportJob.perform_now(video_export.id) }

      video_export.reload
      expect(video_export).to be_failed
      expect(video_export.error_message).to include('Connection refused')
    end
  end
end
