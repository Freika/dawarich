# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Settings, type: :service do
  let(:user) { create(:user, settings: { existing_setting: 'value', theme: 'light' }) }
  let(:settings_data) { { 'theme' => 'dark', 'distance_unit' => 'km', 'new_setting' => 'test' } }
  let(:service) { described_class.new(user, settings_data) }

  describe '#call' do
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

      it 'logs the import process' do
        expect(Rails.logger).to receive(:info).with("Importing settings for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with("Settings import completed")

        service.call
      end
    end

    context 'with nil settings data' do
      let(:settings_data) { nil }

      it 'does not change user settings' do
        expect { service.call }.not_to change { user.reload.settings }
      end

      it 'does not log import process' do
        expect(Rails.logger).not_to receive(:info)

        service.call
      end
    end

    context 'with non-hash settings data' do
      let(:settings_data) { 'invalid_data' }

      it 'does not change user settings' do
        expect { service.call }.not_to change { user.reload.settings }
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

      it 'logs the import process' do
        expect(Rails.logger).to receive(:info).with("Importing settings for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with("Settings import completed")

        service.call
      end
    end
  end
end
