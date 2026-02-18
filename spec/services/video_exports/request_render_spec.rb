# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoExports::RequestRender do
  let(:user) { create(:user) }
  let(:video_export) { create(:video_export, user: user) }

  describe '#call' do
    let(:service) { described_class.new(video_export: video_export) }
    let(:video_service_url) { 'http://dawarich_video:3100' }

    before do
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

        expect(WebMock).to have_requested(:post, "#{video_service_url}/api/render")
          .with { |req| JSON.parse(req.body).key?('callback_url') }
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
  end
end
