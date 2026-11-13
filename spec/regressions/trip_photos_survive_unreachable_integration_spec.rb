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
    'DNS resolution failure' => SocketError.new('Failed to open TCP connection (Hostname not known)'),
    'refused connection' => Errno::ECONNREFUSED,
    'unreachable host' => Errno::EHOSTUNREACH,
    'reset connection' => Errno::ECONNRESET,
    'TLS failure' => OpenSSL::SSL::SSLError.new('unexpected eof while reading')
  }
  unresolved = SocketError.new('Hostname not known')

  def immich_fails_with(failure)
    stub_request(:any, %r{\Ahttp://immich\.invalid/}).to_raise(failure)
  end

  def photoprism_fails_with(failure)
    stub_request(:any, %r{\Ahttp://photoprism\.invalid/}).to_raise(failure)
  end

  describe 'Immich' do
    connection_failures.each do |description, failure|
      it "returns no photos instead of raising on #{description}" do
        immich_fails_with(failure)

        result = nil
        expect { result = Immich::RequestPhotos.new(immich_user).call }.not_to raise_error
        expect(result).to be_nil
      end
    end
  end

  describe 'Photoprism' do
    connection_failures.each do |description, failure|
      it "returns no photos instead of raising on #{description}" do
        photoprism_fails_with(failure)

        result = nil
        expect { result = Photoprism::RequestPhotos.new(photoprism_user).call }.not_to raise_error
        expect(result).to eq([])
      end
    end

    it 'records the failure so a degraded result is not cached as a real one' do
      photoprism_fails_with(unresolved)

      search = Photos::Search.new(photoprism_user)
      search.call

      expect(search.errors).to include(:photoprism)
    end
  end

  describe 'trip page rendering' do
    it 'renders photo sources as empty when the integration host does not resolve' do
      trip = create(:trip, user: immich_user)
      immich_fails_with(unresolved)

      expect { trip.photo_sources }.not_to raise_error
      expect(trip.photo_sources).to be_empty
    end
  end

  describe 'GET /trips/:id' do
    it 'responds with 200 while the configured Immich host does not resolve' do
      trip = create(:trip, user: immich_user)
      immich_fails_with(unresolved)
      sign_in immich_user

      get trip_path(trip)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'connection testing from the integrations settings screen' do
    it 'reports a friendly failure instead of raising when the host does not resolve' do
      immich_fails_with(unresolved)

      result = Immich::ConnectionTester.new('http://immich.invalid', 'key').call

      expect(result[:success]).to be(false)
      expect(result[:error]).to be_present
    end
  end

  describe 'geodata imports' do
    it 'raises so the job can retry instead of recording an empty Immich import' do
      immich_fails_with(unresolved)

      expect { Immich::ImportGeodata.new(immich_user).call }.to raise_error(Integrations::Transport::RetryableError)
      expect(immich_user.imports).to be_empty
    end

    it 'raises so the job can retry instead of recording an empty Photoprism import' do
      photoprism_fails_with(unresolved)

      expect { Photoprism::ImportGeodata.new(photoprism_user).call }.to raise_error(Integrations::Transport::RetryableError)
      expect(photoprism_user.imports).to be_empty
    end

    it 'keeps swallowing a malformed upstream response so the job is not retried forever' do
      stub_request(:post, 'http://immich.invalid/api/search/metadata')
        .to_return(status: 200, body: 'not json', headers: { 'Content-Type' => 'application/json' })

      expect { Immich::ImportGeodata.new(immich_user).call }.not_to raise_error
      expect(immich_user.imports).to be_empty
    end

    it 'lets the Photoprism import job retry a transient connection failure' do
      photoprism_fails_with(unresolved)

      expect { Import::PhotoprismGeodataJob.perform_now(photoprism_user.id) }
        .to have_enqueued_job(Import::PhotoprismGeodataJob).with(photoprism_user.id)
    end
  end

  describe 'thumbnail proxying' do
    it 'responds with 502 instead of raising when the photo host does not resolve' do
      immich_fails_with(unresolved)

      get thumbnail_api_v1_photo_path(id: 'abc'),
          params: { source: 'immich', api_key: immich_user.api_key }

      expect(response).to have_http_status(:bad_gateway)
    end
  end
end
