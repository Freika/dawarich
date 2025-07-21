# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::IncrementalCheckJob, type: :job do
  let(:user) { create(:user) }
  let(:point) { create(:point, user: user) }

  describe '#perform' do
    context 'with valid parameters' do
      let(:processor) { instance_double(Tracks::IncrementalProcessor) }

      it 'calls the incremental processor' do
        expect(Tracks::IncrementalProcessor).to receive(:new)
          .with(user, point)
          .and_return(processor)

        expect(processor).to receive(:call)

        described_class.new.perform(user.id, point.id)
      end
    end
  end

  describe 'job configuration' do
    it 'uses tracks queue' do
      expect(described_class.queue_name).to eq('tracks')
    end
  end

  describe 'integration with ActiveJob' do
    it 'enqueues the job' do
      expect do
        described_class.perform_later(user.id, point.id)
      end.to have_enqueued_job(described_class)
        .with(user.id, point.id)
    end
  end
end
