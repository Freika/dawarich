# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DawarichSettings do
  describe '.video_service_enabled?' do
    around do |example|
      # Clear memoized value between examples
      described_class.instance_variable_set(:@video_service_enabled, nil)
      example.run
    end

    context 'when VIDEO_SERVICE_URL is blank' do
      before { allow(ENV).to receive(:[]).and_call_original }

      it 'returns false' do
        allow(ENV).to receive(:[]).with('VIDEO_SERVICE_URL').and_return(nil)
        expect(described_class.video_service_enabled?).to be false
      end
    end

    context 'when video service is healthy over HTTP' do
      let(:url) { 'http://dawarich_video:3100' }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('VIDEO_SERVICE_URL').and_return(url)
        stub_request(:get, "#{url}/health")
          .to_return(status: 200, body: { status: 'ok' }.to_json)
      end

      it 'returns true' do
        expect(described_class.video_service_enabled?).to be true
      end
    end

    context 'when video service is healthy over HTTPS' do
      let(:url) { 'https://vgs.dawarich.app' }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('VIDEO_SERVICE_URL').and_return(url)
        stub_request(:get, "#{url}/health")
          .to_return(status: 200, body: { status: 'ok' }.to_json)
      end

      it 'returns true' do
        expect(described_class.video_service_enabled?).to be true
      end
    end

    context 'when video service URL has a trailing slash' do
      let(:url) { 'http://dawarich_video:3100/' }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('VIDEO_SERVICE_URL').and_return(url)
        stub_request(:get, 'http://dawarich_video:3100/health')
          .to_return(status: 200, body: { status: 'ok' }.to_json)
      end

      it 'returns true' do
        expect(described_class.video_service_enabled?).to be true
      end
    end
  end
end
