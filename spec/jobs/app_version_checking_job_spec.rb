# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppVersionCheckingJob, type: :job do
  describe '#perform' do
    let(:job) { described_class.new }

    it 'calls CheckAppVersion service' do
      expect(CheckAppVersion).to receive(:new).and_return(instance_double(CheckAppVersion, call: true))

      job.perform
    end
  end
end
