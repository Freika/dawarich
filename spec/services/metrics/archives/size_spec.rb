# frozen_string_literal: true

require 'rails_helper'
require 'prometheus_exporter/client'

RSpec.describe Metrics::Archives::Size do
  describe '#call' do
    subject(:size) { described_class.new(size_bytes: size_bytes).call }

    let(:size_bytes) { 5_000_000 }
    let(:prometheus_client) { instance_double(PrometheusExporter::Client) }

    before do
      allow(PrometheusExporter::Client).to receive(:default).and_return(prometheus_client)
      allow(prometheus_client).to receive(:send_json)
      allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(true)
    end

    it 'sends archive size histogram metric to prometheus' do
      expect(prometheus_client).to receive(:send_json).with(
        {
          type: 'histogram',
          name: 'dawarich_archive_size_bytes',
          value: size_bytes,
          buckets: [
            1_000_000,
            10_000_000,
            50_000_000,
            100_000_000,
            500_000_000,
            1_000_000_000
          ]
        }
      )

      size
    end

    context 'when prometheus exporter is disabled' do
      before do
        allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(false)
      end

      it 'does not send metric' do
        expect(prometheus_client).not_to receive(:send_json)

        size
      end
    end
  end
end
