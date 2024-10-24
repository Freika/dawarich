# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::CalculatingJob, type: :job do
  describe '#perform' do
    let!(:user) { create(:user) }
    let(:start_at) { nil }
    let(:end_at) { nil }

    subject { described_class.perform_now(user.id) }

    before do
      allow(Stats::Calculate).to receive(:new).and_call_original
      allow_any_instance_of(Stats::Calculate).to receive(:call)
    end

    it 'calls Stats::Calculate service' do
      subject

      expect(Stats::Calculate).to have_received(:new).with(user.id, { start_at:, end_at: })
    end

    it 'created notifications' do
      expect { subject }.to change { Notification.count }.by(1)
    end
  end
end
