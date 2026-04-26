# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlaceVisitsCalculatingJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }
    let!(:place) { create(:place, user: user) }

    it 'runs place visit creation for the user without raising' do
      expect { described_class.new.perform(user.id) }.not_to raise_error
    end

    context 'when visits_suggestions_enabled is false' do
      before do
        user.update!(settings: user.settings.merge('visits_suggestions_enabled' => 'false'))
      end

      it 'does not run place visit creation' do
        expect(Places::Visits::Create).not_to receive(:new)

        described_class.new.perform(user.id)
      end
    end
  end
end
