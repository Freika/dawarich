# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AreaVisitsCalculationSchedulingJob, type: :job do
  describe '#perform' do
    let(:area) { create(:area) }
    let(:user) { create(:user) }

    it 'calls the AreaVisitsCalculationService' do
      expect(AreaVisitsCalculatingJob).to receive(:perform_later).with(user.id).and_call_original

      described_class.new.perform
    end
  end
end
