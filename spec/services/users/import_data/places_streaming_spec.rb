# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Places do
  let(:user) { create(:user) }
  let(:logger) { instance_double(Logger, info: nil, debug: nil, error: nil) }
  let(:service) { described_class.new(user, nil, logger: logger) }

  describe '#add / #finalize' do
    it 'creates places in batches and tracks total created' do
      2.times do |index|
        service.add(
          'name' => "Place #{index}",
          'latitude' => 10.0 + index,
          'longitude' => 20.0 + index
        )
      end

      expect { service.finalize }.to change(Place, :count).by(2)
      expect { expect(service.finalize).to eq(2) }.not_to change(Place, :count)
    end

    it 'flushes automatically when the buffer reaches the batch size' do
      stub_const('Users::ImportData::Places::BATCH_SIZE', 2)

      logger_double = instance_double(Logger)
      allow(logger_double).to receive(:info)
      allow(logger_double).to receive(:debug)
      allow(logger_double).to receive(:error)

      buffered_service = described_class.new(user, nil, batch_size: 2, logger: logger_double)

      buffered_service.add('name' => 'First', 'latitude' => 1, 'longitude' => 2)
      expect(Place.count).to eq(0)

      buffered_service.add('name' => 'Second', 'latitude' => 3, 'longitude' => 4)
      expect(Place.count).to eq(2)

      expect(buffered_service.finalize).to eq(2)
      expect { buffered_service.finalize }.not_to change(Place, :count)
    end

    it 'skips invalid records and logs debug messages' do
      allow(logger).to receive(:debug)

      service.add('name' => 'Valid', 'latitude' => 1, 'longitude' => 2)
      service.add('name' => 'Missing coords')

      expect(service.finalize).to eq(1)
      expect(logger).to have_received(:debug).with(/Skipping place with missing required data/)
    end
  end
end
