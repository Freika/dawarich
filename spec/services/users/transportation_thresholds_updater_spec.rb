# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::TransportationThresholdsUpdater do
  let(:user) { create(:user) }

  describe '#call' do
    context 'with non-threshold settings' do
      let(:params) { { 'route_opacity' => 0.5 } }

      it 'updates the settings' do
        result = described_class.new(user, params).call

        expect(result.success?).to be true
        expect(user.reload.settings['route_opacity']).to eq(0.5)
      end

      it 'does not trigger recalculation' do
        result = nil
        expect { result = described_class.new(user, params).call }
          .not_to have_enqueued_job(Tracks::TransportationModeRecalculationJob)
        expect(result.recalculation_triggered?).to be false
      end
    end

    context 'with transportation threshold changes' do
      let(:params) do
        {
          'transportation_thresholds' => {
            'walking_max_speed' => 8,
            'cycling_max_speed' => 50
          }
        }
      end

      it 'updates the settings' do
        result = described_class.new(user, params).call

        expect(result.success?).to be true
        expect(user.reload.settings['transportation_thresholds']['walking_max_speed']).to eq(8)
      end

      it 'triggers recalculation job' do
        result = nil
        expect { result = described_class.new(user, params).call }
          .to have_enqueued_job(Tracks::TransportationModeRecalculationJob).with(user.id)
        expect(result.recalculation_triggered?).to be true
      end
    end

    context 'when thresholds are set to same values' do
      let(:params) do
        {
          'transportation_thresholds' => {
            'walking_max_speed' => 7,
            'cycling_max_speed' => 45
          }
        }
      end

      before do
        user.settings['transportation_thresholds'] = {
          'walking_max_speed' => 7,
          'cycling_max_speed' => 45
        }
        user.save!
      end

      it 'does not trigger recalculation when values unchanged' do
        result = nil
        expect { result = described_class.new(user, params).call }
          .not_to have_enqueued_job(Tracks::TransportationModeRecalculationJob)
        expect(result.recalculation_triggered?).to be false
      end
    end

    context 'when recalculation is in progress' do
      let(:params) do
        {
          'transportation_thresholds' => {
            'walking_max_speed' => 10
          }
        }
      end

      before do
        status = Tracks::TransportationRecalculationStatus.new(user.id)
        status.start(total_tracks: 100)
      end

      it 'returns locked result' do
        result = described_class.new(user, params).call

        expect(result.success?).to be false
        expect(result.error).to include('recalculation is in progress')
      end

      it 'does not update settings' do
        old_settings = user.settings.dup
        described_class.new(user, params).call

        expect(user.reload.settings).to eq(old_settings)
      end
    end

    context 'when save fails' do
      let(:params) { { 'route_opacity' => 0.5 } }

      before do
        allow(user).to receive(:save) do
          user.errors.add(:base, 'Validation failed')
          false
        end
      end

      it 'returns failure result' do
        result = described_class.new(user, params).call

        expect(result.success?).to be false
        expect(result.error).to eq('Validation failed')
      end
    end
  end
end
