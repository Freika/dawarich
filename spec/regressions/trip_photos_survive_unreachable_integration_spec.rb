# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip photos survive an unreachable photo integration' do
  let(:immich_user) do
    create(:user, settings: { 'immich_url' => 'http://immich.invalid', 'immich_api_key' => '123456' })
  end
  let(:photoprism_user) do
    create(:user, settings: { 'photoprism_url' => 'http://photoprism.invalid', 'photoprism_api_key' => '123456' })
  end

  connection_failures = {
    'DNS resolution failure' => -> { raise SocketError, 'Failed to open TCP connection (Hostname not known)' },
    'refused connection' => -> { raise Errno::ECONNREFUSED },
    'unreachable host' => -> { raise Errno::EHOSTUNREACH },
    'reset connection' => -> { raise Errno::ECONNRESET },
    'TLS failure' => -> { raise OpenSSL::SSL::SSLError, 'unexpected eof while reading' }
  }

  describe 'Immich' do
    connection_failures.each do |description, raiser|
      it "returns no photos instead of raising on #{description}" do
        allow(HTTParty).to receive(:post) { raiser.call }

        expect { Immich::RequestPhotos.new(immich_user).call }.not_to raise_error
        expect(Immich::RequestPhotos.new(immich_user).call).to be_nil
      end
    end
  end

  describe 'Photoprism' do
    connection_failures.each do |description, raiser|
      it "returns no photos instead of raising on #{description}" do
        allow(HTTParty).to receive(:get) { raiser.call }

        expect { Photoprism::RequestPhotos.new(photoprism_user).call }.not_to raise_error
        expect(Photoprism::RequestPhotos.new(photoprism_user).call).to eq([])
      end
    end
  end

  describe 'trip page rendering' do
    it 'renders photo sources as empty when the integration host does not resolve' do
      trip = create(:trip, user: immich_user)
      allow(HTTParty).to receive(:post).and_raise(SocketError, 'Hostname not known')

      expect { trip.photo_sources }.not_to raise_error
      expect(trip.photo_sources).to be_empty
    end
  end
end
