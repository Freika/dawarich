# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VisitSuggestingJob, type: :job do
  describe '#perform' do
    let!(:users) { [create(:user)] }

    subject { described_class.perform_now }

    before do
      allow(Visits::Suggest).to receive(:new).and_call_original
      allow_any_instance_of(Visits::Suggest).to receive(:call)
    end

    it 'suggests visits' do
      subject

      expect(Visits::Suggest).to have_received(:new)
    end
  end
end
