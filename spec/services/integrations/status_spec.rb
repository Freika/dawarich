# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Status do
  let!(:user) { create(:user) }

  subject(:status) { described_class.for(user) }

  describe '#configured?' do
    it 'returns false for photo services without credentials' do
      expect(status.configured?('immich')).to be false
      expect(status.configured?('photoprism')).to be false
      expect(status.configured?('airtrail')).to be false
    end

    it 'returns false when only the url is present' do
      user.update!(settings: user.settings.merge('immich_url' => 'https://immich.test'))

      expect(status.configured?('immich')).to be false
    end

    it 'returns true when url and api key are present' do
      user.update!(settings: user.settings.merge('photoprism_url' => 'https://photoprism.test',
                                                 'photoprism_api_key' => 'key'))

      expect(status.configured?('photoprism')).to be true
    end

    it 'returns false for geocoding without any configuration' do
      expect(status.configured?('geocoding')).to be false
    end

    it 'returns true for geocoding with an active service setting' do
      create(:service_setting, user: user, provider: 'photon', active: true,
                               config: { 'host' => 'photon.example.com' })

      expect(status.configured?('geocoding')).to be true
    end

    it 'returns true for geocoding when managed by environment variables' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)

      expect(status.configured?('geocoding')).to be true
    end
  end

  describe '#status' do
    it 'returns nil for an unconfigured service' do
      expect(status.status('immich')).to be_nil
    end

    it 'returns nil for a configured service without a recorded result' do
      user.update!(settings: user.settings.merge('immich_url' => 'https://immich.test',
                                                 'immich_api_key' => 'key'))

      expect(status.status('immich')).to be_nil
    end

    it 'returns :connected when the last connection succeeded' do
      user.update!(settings: user.settings.merge('immich_url' => 'https://immich.test',
                                                 'immich_api_key' => 'key',
                                                 'immich_connection_status' => 'ok'))

      expect(status.status('immich')).to eq(:connected)
    end

    it 'returns :failed when the last connection failed' do
      user.update!(settings: user.settings.merge('airtrail_url' => 'https://airtrail.test',
                                                 'airtrail_api_key' => 'key',
                                                 'airtrail_connection_status' => 'failed'))

      expect(status.status('airtrail')).to eq(:failed)
    end

    it 'ignores a stale recorded result once credentials are removed' do
      user.update!(settings: user.settings.merge('photoprism_connection_status' => 'failed'))

      expect(status.status('photoprism')).to be_nil
    end

    context 'with geocoding' do
      it 'returns nil without an active setting' do
        expect(status.status('geocoding')).to be_nil
      end

      it 'returns :connected when the last test succeeded' do
        create(:service_setting, user: user, provider: 'photon', active: true,
                                 config: { 'host' => 'photon.example.com', 'connection_status' => 'ok' })

        expect(status.status('geocoding')).to eq(:connected)
      end

      it 'returns :failed when the last test failed' do
        create(:service_setting, user: user, provider: 'photon', active: true,
                                 config: { 'host' => 'photon.example.com', 'connection_status' => 'failed' })

        expect(status.status('geocoding')).to eq(:failed)
      end

      it 'returns nil when geocoding is managed by environment variables' do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
        create(:service_setting, user: user, provider: 'photon', active: true,
                                 config: { 'host' => 'photon.example.com', 'connection_status' => 'ok' })

        expect(status.status('geocoding')).to be_nil
      end

      it 'memoizes the lookup so repeated calls run no further queries' do
        create(:service_setting, user: user, provider: 'photon', active: true,
                                 config: { 'host' => 'photon.example.com', 'connection_status' => 'ok' })
        status.status('geocoding')

        queries = 0
        counter = ->(*) { queries += 1 }
        ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
          expect(status.status('geocoding')).to eq(:connected)
        end
        expect(queries).to eq(0)
      end
    end
  end
end
