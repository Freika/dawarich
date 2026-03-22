# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::OutlierDetectionJob, type: :job do
  let(:user) { create(:user) }

  describe '#perform' do
    it 'calls the OutlierDetector service' do
      detector = instance_double(Points::OutlierDetector, call: 0)
      allow(Points::OutlierDetector).to receive(:new)
        .with(user, start_at: nil, end_at: nil)
        .and_return(detector)

      described_class.new.perform(user.id)

      expect(detector).to have_received(:call)
    end

    it 'passes date range when provided' do
      start_at = '2024-05-01T00:00:00Z'
      end_at = '2024-05-01T23:59:59Z'

      detector = instance_double(Points::OutlierDetector, call: 0)
      allow(Points::OutlierDetector).to receive(:new)
        .with(user, start_at: Time.zone.parse(start_at), end_at: Time.zone.parse(end_at))
        .and_return(detector)

      described_class.new.perform(user.id, start_at, end_at)

      expect(detector).to have_received(:call)
    end

    it 'skips if user not found' do
      expect(Points::OutlierDetector).not_to receive(:new)
      described_class.new.perform(-1)
    end

    it 'skips if outlier detection is disabled' do
      user.settings['outlier_detection_enabled'] = false
      user.save!

      expect(Points::OutlierDetector).not_to receive(:new)
      described_class.new.perform(user.id)
    end
  end
end
