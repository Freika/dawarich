# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlaceVisitsCalculatingJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }
    let!(:place) { create(:place, user: user) }

    it 'calls Places::Visits::Create with the user places relation' do
      expect(Places::Visits::Create).to receive(:new).with(
        user,
        satisfy { |places| places.map(&:id) == [place.id] }
      ).and_call_original

      described_class.new.perform(user.id)
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
