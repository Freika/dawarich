# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DawarichSettings do
  describe '.prometheus_exporter_enabled?' do
    before { described_class.instance_variable_set(:@prometheus_exporter_enabled, nil) }
    after  { described_class.instance_variable_set(:@prometheus_exporter_enabled, nil) }

    context 'when PROMETHEUS_EXPORTER_ENABLED is "true"' do
      it 'returns true regardless of HOST/PORT env vars' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PROMETHEUS_EXPORTER_ENABLED').and_return('true')
        expect(described_class.prometheus_exporter_enabled?).to be true
      end
    end

    context 'when PROMETHEUS_EXPORTER_ENABLED is absent' do
      it 'returns false' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PROMETHEUS_EXPORTER_ENABLED').and_return(nil)
        expect(described_class.prometheus_exporter_enabled?).to be false
      end
    end

    context 'when PROMETHEUS_EXPORTER_ENABLED is "false"' do
      it 'returns false' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PROMETHEUS_EXPORTER_ENABLED').and_return('false')
        expect(described_class.prometheus_exporter_enabled?).to be false
      end
    end
  end
end
