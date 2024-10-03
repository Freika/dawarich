# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::WatcherJob, type: :job do
  describe '#perform' do
    it 'calls Imports::Watcher' do
      expect_any_instance_of(Imports::Watcher).to receive(:call)

      described_class.perform_now
    end
  end
end
