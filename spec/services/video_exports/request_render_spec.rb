# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoExports::RequestRender do
  let(:user) { create(:user) }
  let(:video_export) { create(:video_export, user: user) }

  describe '#call' do
    let(:service) { described_class.new(video_export: video_export) }
    let(:video_service_url) { 'http://dawarich_video:3100' }

    before do
      create(:point, user: user, timestamp: 12.hours.ago.to_i, longitude: 13.4, latitude: 52.5)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('VIDEO_SERVICE_URL', anything).and_return(video_service_url)
    end

    context 'when video service responds successfully' do
      before do
        stub_request(:post, "#{video_service_url}/api/render")
          .to_return(status: 200, body: { id: 'render-123', status: 'queued' }.to_json)
      end

      it 'posts track data to the video service' do
        service.call

        expect(WebMock).to(have_requested(:post, "#{video_service_url}/api/render")
          .with { |req| JSON.parse(req.body).key?('callback_url') })
      end
    end

    context 'when video service is unreachable' do
      before do
        stub_request(:post, "#{video_service_url}/api/render")
          .to_raise(Errno::ECONNREFUSED)
      end

      it 'raises an error' do
        expect { service.call }.to raise_error(Errno::ECONNREFUSED)
      end
    end

    context 'when video service returns an error' do
      before do
        stub_request(:post, "#{video_service_url}/api/render")
          .to_return(status: 500, body: { error: 'Internal error' }.to_json)
      end

      it 'raises an error with the response details' do
        expect { service.call }.to raise_error(VideoExports::RequestRender::RenderError)
      end
    end

    context 'when VIDEO_SERVICE_AUTH_TOKEN is set' do
      before do
        stub_request(:post, "#{video_service_url}/api/render")
          .to_return(status: 200, body: { id: 'render-123', status: 'queued' }.to_json)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('VIDEO_SERVICE_AUTH_TOKEN').and_return('test-secret-token')
      end

      it 'includes Authorization header in the request' do
        service.call

        expect(WebMock).to have_requested(:post, "#{video_service_url}/api/render")
          .with(headers: { 'Authorization' => 'Bearer test-secret-token' })
      end
    end

    context 'when VIDEO_SERVICE_AUTH_TOKEN is not set' do
      before do
        stub_request(:post, "#{video_service_url}/api/render")
          .to_return(status: 200, body: { id: 'render-123', status: 'queued' }.to_json)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('VIDEO_SERVICE_AUTH_TOKEN').and_return(nil)
      end

      it 'does not include Authorization header in the request' do
        service.call

        expect(WebMock).to(have_requested(:post, "#{video_service_url}/api/render")
          .with { |req| req.headers.keys.none? { |k| k.casecmp('authorization').zero? } })
      end
    end

    context 'when video service URL uses HTTPS' do
      let(:video_service_url) { 'https://vgs.dawarich.app' }

      before do
        stub_request(:post, "#{video_service_url}/api/render")
          .to_return(status: 200, body: { id: 'render-123', status: 'queued' }.to_json)
      end

      it 'enables SSL on the connection' do
        service.call

        expect(WebMock).to have_requested(:post, "#{video_service_url}/api/render")
      end
    end

    context 'when video service URL has a trailing slash' do
      let(:video_service_url) { 'http://dawarich_video:3100/' }

      before do
        stub_request(:post, 'http://dawarich_video:3100/api/render')
          .to_return(status: 200, body: { id: 'render-123', status: 'queued' }.to_json)
      end

      it 'does not produce a double slash in the request path' do
        service.call

        expect(WebMock).to have_requested(:post, 'http://dawarich_video:3100/api/render')
      end
    end

    context 'when APPLICATION_HOSTS is set' do
      before do
        allow(ENV).to receive(:fetch).with('APPLICATION_HOSTS', anything)
                                     .and_return('app.example.com,192.168.1.10')
        allow(ENV).to receive(:fetch).with('APPLICATION_PROTOCOL', anything)
                                     .and_return('https')
        stub_request(:post, "#{video_service_url}/api/render")
          .to_return(status: 200, body: { id: 'render-123', status: 'queued' }.to_json)
      end

      it 'sends callback_urls for each host' do
        service.call

        expect(WebMock).to(have_requested(:post, "#{video_service_url}/api/render")
          .with do |req|
            body = JSON.parse(req.body)
            urls = body['callback_urls']
            urls.length == 2 &&
              urls[0].start_with?('https://app.example.com') &&
              urls[1].start_with?('https://192.168.1.10')
          end)
      end

      it 'sets callback_url to the first host for backwards compatibility' do
        service.call

        expect(WebMock).to(have_requested(:post, "#{video_service_url}/api/render")
          .with do |req|
            body = JSON.parse(req.body)
            body['callback_url'].start_with?('https://app.example.com')
          end)
      end
    end

    context 'when no coordinates exist for the date range' do
      let(:video_export) do
        create(:video_export, user: user, start_at: 1.year.ago, end_at: 11.months.ago)
      end

      before do
        # Remove the point created in the outer before block by scoping the export
        # to a date range with no points
      end

      it 'raises RenderError with descriptive message' do
        expect { service.call }.to raise_error(
          VideoExports::RequestRender::RenderError,
          'No coordinates found for the given date range'
        )
      end
    end

    context 'when using a track with associated points' do
      let(:track) { create(:track, user: user) }
      let(:video_export) { create(:video_export, user: user, track: track) }

      before do
        create(:point, user: user, track: track, timestamp: 8.hours.ago.to_i,
                       longitude: 13.5, latitude: 52.6)
        create(:point, user: user, track: track, timestamp: 7.hours.ago.to_i,
                       longitude: 13.51, latitude: 52.61)

        stub_request(:post, "#{video_service_url}/api/render")
          .to_return(status: 200, body: { id: 'render-123', status: 'queued' }.to_json)
      end

      it 'uses track points for coordinates' do
        service.call

        expect(WebMock).to(have_requested(:post, "#{video_service_url}/api/render")
          .with do |req|
            coords = JSON.parse(req.body)['coordinates']
            coords.length >= 2
          end)
      end
    end

    context 'when using a track with no associated points' do
      let(:track) do
        create(:track, user: user, start_at: 12.hours.ago, end_at: 6.hours.ago)
      end
      let(:video_export) { create(:video_export, user: user, track: track) }

      before do
        # Points are in the user's time range but NOT linked to the track via track_id
        create(:point, user: user, timestamp: 10.hours.ago.to_i,
                       longitude: 13.4, latitude: 52.5)

        stub_request(:post, "#{video_service_url}/api/render")
          .to_return(status: 200, body: { id: 'render-123', status: 'queued' }.to_json)
      end

      it 'falls back to time-range query using track start_at/end_at' do
        service.call

        expect(WebMock).to(have_requested(:post, "#{video_service_url}/api/render")
          .with do |req|
            coords = JSON.parse(req.body)['coordinates']
            coords.length >= 1
          end)
      end
    end

    context 'when coordinate count exceeds MAX_COORDINATES' do
      before do
        stub_request(:post, "#{video_service_url}/api/render")
          .to_return(status: 200, body: { id: 'render-123', status: 'queued' }.to_json)

        # Stub the constant to a small value for testing
        stub_const('VideoExports::RequestRender::MAX_COORDINATES', 10)

        # Create 25 points (exceeds the stubbed limit of 10)
        25.times do |i|
          create(:point, user: user,
                         timestamp: (24.hours.ago + i.minutes).to_i,
                         longitude: 13.4 + (i * 0.001),
                         latitude: 52.5 + (i * 0.001))
        end
      end

      it 'downsamples coordinates to MAX_COORDINATES' do
        service.call

        expect(WebMock).to(have_requested(:post, "#{video_service_url}/api/render")
          .with do |req|
            coords = JSON.parse(req.body)['coordinates']
            coords.length <= 10
          end)
      end
    end
  end
end
