# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BulkCreatingJob, type: :job do
  describe '#perform' do
    let(:service) { instance_double(Tracks::BulkTrackCreator) }

    before do
      allow(Tracks::BulkTrackCreator).to receive(:new).with(start_at: 'foo', end_at: 'bar', user_ids: [1, 2]).and_return(service)
    end

    it 'calls Tracks::BulkTrackCreator with the correct arguments' do
      expect(service).to receive(:call)

      described_class.new.perform(start_at: 'foo', end_at: 'bar', user_ids: [1, 2])
    end
  end
end
