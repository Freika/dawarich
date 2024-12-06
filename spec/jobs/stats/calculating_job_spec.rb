# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::CalculatingJob, type: :job do
  describe '#perform' do
    let!(:user) { create(:user) }

    subject { described_class.perform_now(user.id, 2024, 1) }

    before do
      allow(Stats::CalculateMonth).to receive(:new).and_call_original
      allow_any_instance_of(Stats::CalculateMonth).to receive(:call)
    end

    it 'calls Stats::CalculateMonth service' do
      subject

      expect(Stats::CalculateMonth).to have_received(:new).with(user.id, 2024, 1)
    end

    context 'when Stats::CalculateMonth raises an error' do
      before do
        allow_any_instance_of(Stats::CalculateMonth).to receive(:call).and_raise(StandardError)
      end

      it 'creates an error notification' do
        expect { subject }.to change { Notification.count }.by(1)
        expect(Notification.last.kind).to eq('error')
      end
    end

    context 'when Stats::CalculateMonth does not raise an error' do
      it 'creates an info notification' do
        expect { subject }.to change { Notification.count }.by(1)
        expect(Notification.last.kind).to eq('info')
      end
    end
  end
end
