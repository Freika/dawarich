# frozen_string_literal: true

require 'rails_helper'
require 'prometheus_exporter/client'

RSpec.describe Metrics::Archives::CountMismatch do
  describe '#call' do
    subject(:count_mismatch) do
      described_class.new(
        user_id: user_id,
        year: year,
        month: month,
        expected: expected,
        actual: actual
      ).call
    end

    let(:user_id) { 123 }
    let(:year) { 2025 }
    let(:month) { 1 }
    let(:expected) { 100 }
    let(:actual) { 95 }
    let(:prometheus_client) { instance_double(PrometheusExporter::Client) }

    before do
      allow(PrometheusExporter::Client).to receive(:default).and_return(prometheus_client)
      allow(prometheus_client).to receive(:send_json)
      allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(true)
    end

    it 'sends count mismatch counter metric' do
      expect(prometheus_client).to receive(:send_json).with(
        {
          type: 'counter',
          name: 'dawarich_archive_count_mismatches_total',
          value: 1,
          labels: {
            year: year.to_s,
            month: month.to_s
          }
        }
      )

      count_mismatch
    end

    it 'sends count difference gauge metric' do
      expect(prometheus_client).to receive(:send_json).with(
        {
          type: 'gauge',
          name: 'dawarich_archive_count_difference',
          value: 5,
          labels: {
            user_id: user_id.to_s
          }
        }
      )

      count_mismatch
    end

    context 'when prometheus exporter is disabled' do
      before do
        allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(false)
      end

      it 'does not send metrics' do
        expect(prometheus_client).not_to receive(:send_json)

        count_mismatch
      end
    end
  end
end
