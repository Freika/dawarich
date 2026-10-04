# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::WatcherJob, type: :job do
  it 'skips the Rails watcher while its cron belongs to Oban' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    job_owner!('cron:watcher_job', :oban)
    expect_any_instance_of(Imports::Watcher).not_to receive(:call)
    described_class.perform_now
  end

  describe '#perform' do
    context 'when Dawarich is not self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'does not call Imports::Watcher' do
        expect_any_instance_of(Imports::Watcher).not_to receive(:call)

        described_class.perform_now
      end
    end

    context 'when Dawarich is self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end

      it 'calls Imports::Watcher' do
        expect_any_instance_of(Imports::Watcher).to receive(:call)

        described_class.perform_now
      end
    end
  end
end
