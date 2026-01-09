# frozen_string_literal: true

require 'rails_helper'
require 'prometheus_exporter/client'

RSpec.describe Metrics::Archives::Operation do
  describe '#call' do
    subject(:operation) { described_class.new(operation: operation_type, status: status).call }

    let(:operation_type) { 'archive' }
    let(:status) { 'success' }
    let(:prometheus_client) { instance_double(PrometheusExporter::Client) }

    before do
      allow(PrometheusExporter::Client).to receive(:default).and_return(prometheus_client)
      allow(prometheus_client).to receive(:send_json)
      allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(true)
    end

    it 'sends operation metric to prometheus' do
      expect(prometheus_client).to receive(:send_json).with(
        {
          type: 'counter',
          name: 'dawarich_archive_operations_total',
          value: 1,
          labels: {
            operation: operation_type,
            status: status
          }
        }
      )

      operation
    end

    context 'when prometheus exporter is disabled' do
      before do
        allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(false)
      end

      it 'does not send metric' do
        expect(prometheus_client).not_to receive(:send_json)

        operation
      end
    end

    context 'when operation fails' do
      let(:status) { 'failure' }

      it 'sends failure metric' do
        expect(prometheus_client).to receive(:send_json).with(
          hash_including(
            labels: hash_including(status: 'failure')
          )
        )

        operation
      end
    end
  end
end
