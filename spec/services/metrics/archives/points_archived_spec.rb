# frozen_string_literal: true

require 'rails_helper'
require 'prometheus_exporter/client'

RSpec.describe Metrics::Archives::PointsArchived do
  describe '#call' do
    subject(:points_archived) { described_class.new(count: count, operation: operation).call }

    let(:count) { 250 }
    let(:operation) { 'added' }
    let(:prometheus_client) { instance_double(PrometheusExporter::Client) }

    before do
      allow(PrometheusExporter::Client).to receive(:default).and_return(prometheus_client)
      allow(prometheus_client).to receive(:send_json)
      allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(true)
    end

    it 'sends points archived metric to prometheus' do
      expect(prometheus_client).to receive(:send_json).with(
        {
          type: 'counter',
          name: 'dawarich_archive_points_total',
          value: count,
          labels: {
            operation: operation
          }
        }
      )

      points_archived
    end

    context 'when operation is removed' do
      let(:operation) { 'removed' }

      it 'sends removed operation metric' do
        expect(prometheus_client).to receive(:send_json).with(
          hash_including(
            labels: { operation: 'removed' }
          )
        )

        points_archived
      end
    end

    context 'when prometheus exporter is disabled' do
      before do
        allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(false)
      end

      it 'does not send metric' do
        expect(prometheus_client).not_to receive(:send_json)

        points_archived
      end
    end
  end
end
