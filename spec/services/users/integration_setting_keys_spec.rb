# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::IntegrationSettingKeys do
  describe '.without_credentials' do
    it 'removes a user and password from the URL' do
      expect(described_class.without_credentials('http://user:pass@immich.lan:2283/base?x=1'))
        .to eq('http://immich.lan:2283/base?x=1')
    end

    it 'removes a user without a password' do
      expect(described_class.without_credentials('https://token@immich.lan')).to eq('https://immich.lan')
    end

    it 'leaves a URL without credentials alone, even with @ in its path or query' do
      url = 'https://immich.lan/a@b?mail=x@y'

      expect(described_class.without_credentials(url)).to eq(url)
    end

    it 'still removes credentials from a URL that cannot be parsed' do
      expect(described_class.without_credentials('http://user:pa ss@immich.lan/')).to eq('http://immich.lan/')
    end

    it 'removes credentials from a URL saved without a scheme' do
      expect(described_class.without_credentials('user:pass@immich.lan')).to eq('immich.lan')
    end

    it 'removes credentials when the password itself contains @' do
      expect(described_class.without_credentials('http://user:p@ss@immich.lan/')).to eq('http://immich.lan/')
    end

    it 'passes through nil and non-strings' do
      expect(described_class.without_credentials(nil)).to be_nil
      expect(described_class.without_credentials(42)).to eq(42)
    end
  end

  describe '.redact' do
    it 'drops secrets and strips credentials from integration URLs only' do
      redacted = described_class.redact(
        'immich_api_key' => 'secret', 'immich_url' => 'http://u:p@immich.lan',
        'teslamate_last_synced_url' => 'http://u:p@tesla.lan', 'teslamate_username' => 'proxy',
        'maps_maplibre_tiles_url' => 'https://k:v@tiles.example/{z}/{x}/{y}.png'
      )

      expect(redacted).to eq(
        'immich_url' => 'http://immich.lan', 'teslamate_last_synced_url' => 'http://tesla.lan',
        'teslamate_username' => 'proxy', 'maps_maplibre_tiles_url' => 'https://k:v@tiles.example/{z}/{x}/{y}.png'
      )
    end
  end

  it 'has every secret covered by the JSON settings log filter' do
    expect(SENSITIVE_SETTINGS_KEYS).to match_array(described_class::SECRETS)
  end

  describe '.connection_key?' do
    it 'matches integration settings and nothing else' do
      expect(%w[immich_url photoprism_api_key airtrail_last_synced_at teslamate_processing_pending])
        .to all(satisfy { |key| described_class.connection_key?(key) })
      expect(%w[timezone maps_maplibre_tiles_url min_minutes_spent_in_city])
        .to all(satisfy { |key| !described_class.connection_key?(key) })
    end
  end
end
