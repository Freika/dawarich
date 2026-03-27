# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AreaVisitsCalculatingJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }
    let!(:area) { create(:area, user:) }

    it 'calls Areas::Visits::Create with user areas' do
      expect(Areas::Visits::Create).to receive(:new).with(user, [area]).and_call_original

      described_class.perform_now(user.id)
    end

    it 'skips gracefully when user is not found' do
      expect(Areas::Visits::Create).not_to receive(:new)

      described_class.perform_now(-1)
    end
  end
end
