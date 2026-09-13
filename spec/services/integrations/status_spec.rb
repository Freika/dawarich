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
  end
end
