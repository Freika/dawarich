# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AreaVisitsCalculationSchedulingJob, type: :job do
  describe '#perform' do
    let!(:user) { create(:user) }
    let(:area) { create(:area, user: user) }

    it 'enqueues area and place visit jobs when visit suggestions are enabled' do
      expect { described_class.new.perform }
        .to have_enqueued_job(AreaVisitsCalculatingJob).with(user.id)
        .and have_enqueued_job(PlaceVisitsCalculatingJob).with(user.id)
    end

    context 'when visits_suggestions_enabled is false' do
      let!(:user_disabled) do
        u = create(:user)
        u.update!(settings: u.settings.merge('visits_suggestions_enabled' => 'false'))
        u
      end

      it 'does not enqueue area or place visit jobs for that user' do
        described_class.new.perform

        expect(AreaVisitsCalculatingJob).not_to have_been_enqueued.with(user_disabled.id)
        expect(PlaceVisitsCalculatingJob).not_to have_been_enqueued.with(user_disabled.id)
      end
    end
  end
end
