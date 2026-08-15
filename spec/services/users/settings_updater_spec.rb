# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::SettingsUpdater do
  let(:user) { create(:user) }

  describe '#call' do
    context 'with general settings' do
      let(:params) { { 'route_opacity' => 0.5 } }

      it 'updates the settings without triggering recalculation' do
        result = nil
        expect { result = described_class.new(user, params).call }
          .not_to have_enqueued_job(TransportationModes::UserReclassifyJob)

        expect(result.success?).to be true
        expect(result.recalculation_triggered?).to be false
        expect(user.reload.settings['route_opacity']).to eq(0.5)
      end
    end

    context 'when the enabled modes allowlist changes' do
      let(:params) { { 'enabled_transportation_modes' => %w[walking cycling] } }

      it 'persists the allowlist and triggers reclassification' do
        result = nil
        expect { result = described_class.new(user, params).call }
          .to have_enqueued_job(TransportationModes::UserReclassifyJob).with(user.id)

        expect(result.success?).to be true
        expect(result.recalculation_triggered?).to be true
        expect(user.reload.settings['enabled_transportation_modes']).to eq(%w[walking cycling])
      end
    end

    context 'when the allowlist is unchanged' do
      before do
        user.settings['enabled_transportation_modes'] = %w[walking cycling]
        user.save!
      end

      it 'does not trigger reclassification' do
        result = nil
        expect { result = described_class.new(user, 'enabled_transportation_modes' => %w[walking cycling]).call }
          .not_to have_enqueued_job(TransportationModes::UserReclassifyJob)
        expect(result.recalculation_triggered?).to be false
      end
    end

    context 'when the allowlist contains no valid mode' do
      it 'rejects the update' do
        result = described_class.new(user, 'enabled_transportation_modes' => %w[teleporting]).call
        expect(result.success?).to be false
        expect(result.error).to be_present
      end
    end

    context 'when recalculation is in progress' do
      before do
        allow_any_instance_of(Tracks::TransportationRecalculationStatus)
          .to receive(:in_progress?).and_return(true)
      end

      it 'locks allowlist changes' do
        result = described_class.new(user, 'enabled_transportation_modes' => %w[walking]).call
        expect(result.success?).to be false
      end

      it 'still allows unrelated settings changes' do
        result = described_class.new(user, 'route_opacity' => 0.7).call
        expect(result.success?).to be true
      end
    end

    context 'with an invalid timezone' do
      it 'ignores the timezone value' do
        described_class.new(user, 'timezone' => 'Not/AZone').call
        expect(user.reload.settings['timezone']).not_to eq('Not/AZone')
      end
    end
  end
end
