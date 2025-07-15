# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppVersionCheckingJob, type: :job do
  describe '#perform' do
    let(:job) { described_class.new }

    it 'calls CheckAppVersion service' do
      expect(CheckAppVersion).to receive(:new).and_return(instance_double(CheckAppVersion, call: true))

      job.perform
    end

    context 'when app is not self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'does not call CheckAppVersion service' do
        expect(CheckAppVersion).not_to receive(:new)

        job.perform
      end
    end
  end
end
