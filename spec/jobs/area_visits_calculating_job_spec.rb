# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AreaVisitsCalculatingJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }
    let(:area) { create(:area, user:) }

    it 'calls the AreaVisitsCalculationService' do
      Sidekiq::Testing.inline! do
        expect(Areas::Visits::Create).to receive(:new).with(user, [area]).and_call_original

        described_class.new.perform(user.id)
      end
    end
  end
end
