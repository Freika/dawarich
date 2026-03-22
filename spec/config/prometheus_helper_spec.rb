# frozen_string_literal: true

require 'rails_helper'
require_relative '../../config/prometheus_helper'

RSpec.describe PrometheusHelper do
  before { described_class.reset! }

  after { described_class.reset! }

  describe '.ensure_reachable!' do
    context 'when host is a local address' do
      %w[localhost 127.0.0.1 0.0.0.0 :: ANY].each do |host|
        it "returns true for #{host} without attempting connection" do
          allow(ENV).to receive(:fetch).and_call_original
          allow(ENV).to receive(:fetch).with('PROMETHEUS_EXPORTER_HOST', 'localhost').and_return(host)
          allow(ENV).to receive(:fetch).with('PROMETHEUS_EXPORTER_PORT', 9394).and_return('9394')

          expect(Socket).not_to receive(:new)
          expect(described_class.ensure_reachable!).to be true
        end
      end
    end

    context 'when host is a remote address that is unreachable' do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch)
          .with('PROMETHEUS_EXPORTER_HOST', 'localhost').and_return('nonexistent.host.invalid')
        allow(ENV).to receive(:fetch).with('PROMETHEUS_EXPORTER_PORT', 9394).and_return('9394')
        # Skip retry delays in tests
        allow(described_class).to receive(:sleep)
      end

      it 'returns false' do
        expect(described_class.ensure_reachable!).to be false
      end

      it 'logs a warning with retry count' do
        expect(Rails.logger).to receive(:warn).with(/not reachable after 3 attempts/)
        described_class.ensure_reachable!
      end

      it 'retries before giving up' do
        expect(Rails.logger).to receive(:info).with(/retrying/).at_least(:once)
        allow(Rails.logger).to receive(:warn)
        described_class.ensure_reachable!
      end
    end

    context 'when connection is refused' do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch)
          .with('PROMETHEUS_EXPORTER_HOST', 'localhost').and_return('remote-exporter')
        allow(ENV).to receive(:fetch).with('PROMETHEUS_EXPORTER_PORT', 9394).and_return('9394')
        allow(described_class).to receive(:sleep)

        socket = instance_double(Socket)
        allow(Socket).to receive(:new).and_return(socket)
        allow(Socket).to receive(:sockaddr_in).and_return('sockaddr')
        allow(socket).to receive(:connect_nonblock).and_raise(Errno::ECONNREFUSED)
        allow(socket).to receive(:close)
      end

      it 'returns false after retries' do
        expect(described_class.ensure_reachable!).to be false
      end
    end

    context 'when connection succeeds on retry' do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch)
          .with('PROMETHEUS_EXPORTER_HOST', 'localhost').and_return('remote-exporter')
        allow(ENV).to receive(:fetch).with('PROMETHEUS_EXPORTER_PORT', 9394).and_return('9394')
        allow(described_class).to receive(:sleep)

        socket = instance_double(Socket)
        allow(Socket).to receive(:new).and_return(socket)
        allow(Socket).to receive(:sockaddr_in).and_return('sockaddr')
        allow(socket).to receive(:close)

        # Fail first attempt, succeed second
        call_count = 0
        allow(socket).to receive(:connect_nonblock) do
          call_count += 1
          raise Errno::ECONNREFUSED if call_count == 1

          true
        end
      end

      it 'returns true' do
        expect(described_class.ensure_reachable!).to be true
      end
    end

    context 'when DNS resolution fails' do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch)
          .with('PROMETHEUS_EXPORTER_HOST', 'localhost').and_return('remote-exporter')
        allow(ENV).to receive(:fetch).with('PROMETHEUS_EXPORTER_PORT', 9394).and_return('9394')
        allow(described_class).to receive(:sleep)

        socket = instance_double(Socket)
        allow(Socket).to receive(:new).and_return(socket)
        allow(Socket).to receive(:sockaddr_in)
          .and_raise(SocketError, 'getaddrinfo: Name or service not known')
        allow(socket).to receive(:close)
      end

      it 'returns false' do
        expect(described_class.ensure_reachable!).to be false
      end
    end

    it 'caches the result across calls' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('PROMETHEUS_EXPORTER_HOST', 'localhost').and_return('localhost')
      allow(ENV).to receive(:fetch).with('PROMETHEUS_EXPORTER_PORT', 9394).and_return('9394')

      result1 = described_class.ensure_reachable!
      result2 = described_class.ensure_reachable!

      expect(result1).to eq(result2)
    end
  end
end
