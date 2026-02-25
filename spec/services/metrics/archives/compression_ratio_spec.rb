# frozen_string_literal: true

require 'rails_helper'
require 'prometheus_exporter/client'

RSpec.describe Metrics::Archives::CompressionRatio do
  describe '#call' do
    subject(:compression_ratio) do
      described_class.new(
        original_size: original_size,
        compressed_size: compressed_size
      ).call
    end

    let(:original_size) { 10_000 }
    let(:compressed_size) { 3_000 }
    let(:expected_ratio) { 0.3 }
    let(:prometheus_client) { instance_double(PrometheusExporter::Client) }

    before do
      allow(PrometheusExporter::Client).to receive(:default).and_return(prometheus_client)
      allow(prometheus_client).to receive(:send_json)
      allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(true)
    end

    it 'sends compression ratio histogram metric to prometheus' do
      expect(prometheus_client).to receive(:send_json).with(
        {
          type: 'histogram',
          name: 'dawarich_archive_compression_ratio',
          value: expected_ratio,
          buckets: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        }
      )

      compression_ratio
    end

    context 'when prometheus exporter is disabled' do
      before do
        allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(false)
      end

      it 'does not send metric' do
        expect(prometheus_client).not_to receive(:send_json)

        compression_ratio
      end
    end
  end
end
