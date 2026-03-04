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

    context 'when APPLICATION_HOST is set' do
      let(:app_host) { 'https://dawarich.example.com' }

      before do
        allow(ENV).to receive(:fetch).with('APPLICATION_HOST', anything).and_return(app_host)
        stub_request(:post, "#{video_service_url}/api/render")
          .to_return(status: 200, body: { id: 'render-123', status: 'queued' }.to_json)
      end

      it 'uses APPLICATION_HOST in the callback URL' do
        service.call

        expect(WebMock).to(have_requested(:post, "#{video_service_url}/api/render")
          .with do |req|
            callback = JSON.parse(req.body)['callback_url']
            callback.start_with?(app_host)
          end)
      end
    end
  end
end
