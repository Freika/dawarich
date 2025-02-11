# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TelemetrySendingJob, type: :job do
  describe '#perform' do
    let(:gather_service) { instance_double(Telemetry::Gather) }
    let(:send_service) { instance_double(Telemetry::Send) }
    let(:telemetry_data) { { some: 'data' } }

    before do
      allow(Telemetry::Gather).to receive(:new).and_return(gather_service)
      allow(gather_service).to receive(:call).and_return(telemetry_data)
      allow(Telemetry::Send).to receive(:new).with(telemetry_data).and_return(send_service)
      allow(send_service).to receive(:call)
    end

    context 'with default env' do
      it 'does not send telemetry data' do
        described_class.perform_now

        expect(send_service).not_to have_received(:call)
      end
    end

    context 'when ENABLE_TELEMETRY is set to true' do
      before do
        stub_const('ENV', ENV.to_h.merge('ENABLE_TELEMETRY' => 'true'))
      end

        it 'gathers telemetry data and sends it' do
        described_class.perform_now

        expect(gather_service).to have_received(:call)
        expect(send_service).to have_received(:call)
      end
    end
  end
end
