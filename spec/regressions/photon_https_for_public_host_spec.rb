# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DawarichSettings do
  before do
    described_class.instance_variables.each do |ivar|
      described_class.remove_instance_variable(ivar)
    end
  end

  describe '.photon_use_https?' do
    context 'when the host is a known HTTPS-only public host and the flag is off' do
      before do
        configure_instance_geocoding(photon_api_host: 'photon.dawarich.app', photon_api_use_https: false)
      end

      it 'forces HTTPS regardless of the flag' do
        expect(described_class.photon_use_https?).to be true
      end
    end

    context 'when the host is photon.komoot.io and the flag is off' do
      before do
        configure_instance_geocoding(photon_api_host: 'photon.komoot.io', photon_api_use_https: false)
      end

      it 'forces HTTPS' do
        expect(described_class.photon_use_https?).to be true
      end
    end

    context 'when the public host carries a port and surrounding whitespace' do
      before do
        configure_instance_geocoding(photon_api_host: '  Photon.Dawarich.App:443 ', photon_api_use_https: false)
      end

      it 'still forces HTTPS' do
        expect(described_class.photon_use_https?).to be true
      end
    end

    context 'when the host is a self-hosted photon and the flag is off' do
      before do
        configure_instance_geocoding(photon_api_host: 'localhost:2322', photon_api_use_https: false)
      end

      it 'leaves HTTP in place' do
        expect(described_class.photon_use_https?).to be false
      end
    end

    context 'when the host is a self-hosted photon and the flag is on' do
      before do
        configure_instance_geocoding(photon_api_host: 'photon.internal.example', photon_api_use_https: true)
      end

      it 'honors the flag' do
        expect(described_class.photon_use_https?).to be true
      end
    end
  end
end
