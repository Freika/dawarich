# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VisitSuggestingJob, type: :job do
  let!(:users) { [create(:user)] }

  describe '#perform' do
    subject { described_class.perform_now }

    before do
      allow(Visits::Suggest).to receive(:new).and_call_original
      allow_any_instance_of(Visits::Suggest).to receive(:call)
    end

    context 'when user has no tracked points' do
      it 'does not suggest visits' do
        subject

        expect(Visits::Suggest).not_to have_received(:new)
      end
    end

    context 'when user has tracked points' do
      let!(:tracked_point) { create(:point, user: users.first) }

      it 'suggests visits' do
        subject

        expect(Visits::Suggest).to have_received(:new)
      end
    end
  end
end
