# frozen_string_literal: true

require 'rails_helper'

RSpec.describe YearlyDigests::CalculatingJob, type: :job do
  describe '#perform' do
    let!(:user) { create(:user) }
    let(:year) { 2024 }

    subject { described_class.perform_now(user.id, year) }

    before do
      allow(YearlyDigests::CalculateYear).to receive(:new).and_call_original
      allow_any_instance_of(YearlyDigests::CalculateYear).to receive(:call)
    end

    it 'calls YearlyDigests::CalculateYear service' do
      subject

      expect(YearlyDigests::CalculateYear).to have_received(:new).with(user.id, year)
    end

    it 'enqueues to the digests queue' do
      expect(described_class.new.queue_name).to eq('digests')
    end

    context 'when YearlyDigests::CalculateYear raises an error' do
      before do
        allow_any_instance_of(YearlyDigests::CalculateYear).to receive(:call).and_raise(StandardError.new('Test error'))
      end

      it 'creates an error notification' do
        expect { subject }.to change { Notification.count }.by(1)
        expect(Notification.last.kind).to eq('error')
        expect(Notification.last.title).to include('Year-End Digest')
      end
    end

    context 'when user does not exist' do
      before do
        allow_any_instance_of(YearlyDigests::CalculateYear).to receive(:call).and_raise(ActiveRecord::RecordNotFound)
      end

      it 'does not raise error' do
        expect { subject }.not_to raise_error
      end
    end
  end
end
