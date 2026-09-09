# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip photos survive an unreachable photo integration', type: :request do
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

        result = nil
        expect { result = Immich::RequestPhotos.new(immich_user).call }.not_to raise_error
        expect(result).to be_nil
      end
    end
  end

  describe 'Photoprism' do
    connection_failures.each do |description, raiser|
      it "returns no photos instead of raising on #{description}" do
        allow(HTTParty).to receive(:get) { raiser.call }

        result = nil
        expect { result = Photoprism::RequestPhotos.new(photoprism_user).call }.not_to raise_error
        expect(result).to eq([])
      end
    end

    it 'records the failure so a degraded result is not cached as a real one' do
      allow(HTTParty).to receive(:get).and_raise(SocketError, 'Hostname not known')

      search = Photos::Search.new(photoprism_user)
      search.call

      expect(search.errors).to include(:photoprism)
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

  describe 'GET /trips/:id' do
    it 'responds with 200 while the configured Immich host does not resolve' do
      trip = create(:trip, user: immich_user)
      allow(HTTParty).to receive(:post).and_raise(SocketError, 'Hostname not known')
      sign_in immich_user

      get trip_path(trip)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'connection testing from the integrations settings screen' do
    it 'reports a friendly failure instead of raising when the host does not resolve' do
      allow(HTTParty).to receive(:post).and_raise(SocketError, 'Hostname not known')

      result = Immich::ConnectionTester.new('http://immich.invalid', 'key').call

      expect(result[:success]).to be(false)
      expect(result[:error]).to be_present
    end
  end

  describe 'geodata imports' do
    it 'raises so the job can retry instead of recording an empty Immich import' do
      allow(HTTParty).to receive(:post).and_raise(SocketError, 'Hostname not known')

      expect { Immich::ImportGeodata.new(immich_user).call }.to raise_error(SocketError)
      expect(immich_user.imports).to be_empty
    end

    it 'raises so the job can retry instead of recording an empty Photoprism import' do
      allow(HTTParty).to receive(:get).and_raise(SocketError, 'Hostname not known')

      expect { Photoprism::ImportGeodata.new(photoprism_user).call }.to raise_error(SocketError)
      expect(photoprism_user.imports).to be_empty
    end

    it 'keeps swallowing a malformed upstream response so the job is not retried forever' do
      allow(HTTParty).to receive(:post).and_raise(JSON::ParserError, 'unexpected token')

      expect { Immich::ImportGeodata.new(immich_user).call }.not_to raise_error
      expect(immich_user.imports).to be_empty
    end

    it 'lets the Photoprism import job retry a transient connection failure' do
      allow(HTTParty).to receive(:get).and_raise(SocketError, 'Hostname not known')

      expect { Import::PhotoprismGeodataJob.perform_now(photoprism_user.id) }
        .to have_enqueued_job(Import::PhotoprismGeodataJob).with(photoprism_user.id)
    end
  end

  describe 'thumbnail proxying' do
    it 'responds with 502 instead of raising when the photo host does not resolve' do
      allow(HTTParty).to receive(:get).and_raise(SocketError, 'Hostname not known')

      get thumbnail_api_v1_photo_path(id: 'abc'),
          params: { source: 'immich', api_key: immich_user.api_key }

      expect(response).to have_http_status(:bad_gateway)
    end
  end
end
