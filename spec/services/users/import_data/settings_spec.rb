# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Settings, type: :service do
  let(:user) { create(:user, settings: { existing_setting: 'value', theme: 'light' }) }
  let(:settings_data) { { 'theme' => 'dark', 'distance_unit' => 'km', 'new_setting' => 'test' } }
  let(:service) { described_class.new(user, settings_data) }

  describe '#call' do
    it 'preserves imported JSON boolean opt-ins when read back' do
      [false, true].each do |enabled|
        expect(described_class.new(user, { 'visits_suggestions_enabled' => enabled }).call).to be(true)
        expect(user.reload.settings['visits_suggestions_enabled']).to be(enabled)
        expect(user.safe_settings.visits_suggestions_enabled?).to be(enabled)
      end
    end

    context 'with valid settings data' do
      it 'merges imported settings with existing settings' do
        expect { service.call }.to change { user.reload.settings }.to(
          'existing_setting' => 'value',
          'theme' => 'dark',
          'distance_unit' => 'km',
          'new_setting' => 'test'
        )
      end

      it 'gives precedence to imported settings over existing ones' do
        service.call

        expect(user.reload.settings['theme']).to eq('dark')
      end

      it 'logs the import by user id, without the email or the settings' do
        logged = []
        allow(Rails.logger).to receive(:info) { |message| logged << message }

        service.call

        expect(logged).to eq(["Importing settings for user #{user.id}", 'Settings import completed'])
      end
    end

    context 'with integration connection settings in the archive' do
      let(:user) do
        create(:user, settings: { 'immich_url' => 'https://mine.example.com', 'immich_api_key' => 'my-key',
                                  'immich_connection_status' => 'ok' })
      end
      let(:settings_data) do
        { 'immich_url' => 'https://archive.example.com', 'immich_api_key' => 'archive-key',
          'immich_connection_status' => 'failed', 'photoprism_url' => 'https://photoprism.example.com',
          'airtrail_url' => 'https://airtrail.example.com', 'airtrail_last_synced_at' => '2026-01-01T00:00:00Z',
          'teslamate_url' => 'https://teslamate.example.com', 'teslamate_username' => 'proxy',
          'teslamate_password' => 'secret', 'teslamate_skip_ssl_verification' => true,
          'min_minutes_spent_in_city' => 45 }
      end

      it 'leaves the account connection to an integration exactly as it was' do
        service.call

        expect(user.reload.settings).to include('immich_url' => 'https://mine.example.com',
                                                'immich_api_key' => 'my-key',
                                                'immich_connection_status' => 'ok')
      end

      it 'does not connect an integration the account did not have' do
        service.call

        connection_keys = user.reload.settings.keys.grep(/\A(photoprism|airtrail|teslamate)_/)
        expect(connection_keys).to be_empty
      end

      it 'still imports the other settings' do
        service.call

        expect(user.reload.settings['min_minutes_spent_in_city']).to eq(45)
      end
    end

    context 'with nil settings data' do
      let(:settings_data) { nil }

      it 'does not change user settings' do
        expect { service.call }.not_to(change { user.reload.settings })
      end

      it 'does not log import process' do
        expect(Rails.logger).not_to receive(:info)

        service.call
      end
    end

    context 'with non-hash settings data' do
      let(:settings_data) { 'invalid_data' }

      it 'does not change user settings' do
        expect { service.call }.not_to(change { user.reload.settings })
      end

      it 'does not log import process' do
        expect(Rails.logger).not_to receive(:info)

        service.call
      end
    end

    context 'with empty settings data' do
      let(:settings_data) { {} }

      it 'preserves existing settings without adding new ones' do
        original_settings = user.settings.dup

        service.call

        expect(user.reload.settings).to eq(original_settings)
      end

      it 'logs the import by user id, without the email or the settings' do
        logged = []
        allow(Rails.logger).to receive(:info) { |message| logged << message }

        service.call

        expect(logged).to eq(["Importing settings for user #{user.id}", 'Settings import completed'])
      end
    end

    context 'with malformed imported locale values' do
      it 'leaves locale resolution safe and unset' do
        [false, 42, { 'language' => 'fr' }].each do |locale|
          imported_user = create(:user)

          expect(described_class.new(imported_user, { 'locale' => locale }).call).to be(true)
          expect(imported_user.reload.preferred_locale).to be_nil
        end
      end
    end
  end
end
