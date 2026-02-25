# frozen_string_literal: true

require 'rails_helper'
require 'prometheus_exporter/client'

RSpec.describe Metrics::Archives::Verification do
  describe '#call' do
    subject(:verification) do
      described_class.new(
        duration_seconds: duration_seconds,
        status: status,
        check_name: check_name
      ).call
    end

    let(:duration_seconds) { 2.5 }
    let(:status) { 'success' }
    let(:check_name) { nil }
    let(:prometheus_client) { instance_double(PrometheusExporter::Client) }

    before do
      allow(PrometheusExporter::Client).to receive(:default).and_return(prometheus_client)
      allow(prometheus_client).to receive(:send_json)
      allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(true)
    end

    it 'sends verification duration histogram metric' do
      expect(prometheus_client).to receive(:send_json).with(
        {
          type: 'histogram',
          name: 'dawarich_archive_verification_duration_seconds',
          value: duration_seconds,
          labels: {
            status: status
          },
          buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60]
        }
      )

      verification
    end

    context 'when verification fails with check name' do
      let(:status) { 'failure' }
      let(:check_name) { 'count_mismatch' }

      it 'sends verification failure counter metric' do
        expect(prometheus_client).to receive(:send_json).with(
          hash_including(
            type: 'counter',
            name: 'dawarich_archive_verification_failures_total',
            value: 1,
            labels: {
              check: check_name
            }
          )
        )

        verification
      end
    end

    context 'when prometheus exporter is disabled' do
      before do
        allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(false)
      end

      it 'does not send metrics' do
        expect(prometheus_client).not_to receive(:send_json)

        verification
      end
    end
  end
end
