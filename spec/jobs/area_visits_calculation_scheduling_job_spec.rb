# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AreaVisitsCalculationSchedulingJob, type: :job do
  describe '#perform' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }

    it 'calls the AreaVisitsCalculationService' do
      # Create users first
      user1
      user2

      # Mock User.find_each to only return our test users
      allow(User).to receive(:find_each).and_yield(user1).and_yield(user2)

      expect(AreaVisitsCalculatingJob).to receive(:perform_later).with(user1.id).and_call_original
      expect(AreaVisitsCalculatingJob).to receive(:perform_later).with(user2.id).and_call_original

      described_class.new.perform
    end
  end
end
