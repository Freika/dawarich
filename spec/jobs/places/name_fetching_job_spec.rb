# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::NameFetchingJob, type: :job do
  describe '#perform' do
    let(:place) { create(:place, name: Place::DEFAULT_NAME) }

    it 'calls NameFetcher for the place' do
      name_fetcher = instance_double(Places::NameFetcher)
      allow(Places::NameFetcher).to receive(:new).with(place).and_return(name_fetcher)
      allow(name_fetcher).to receive(:call)

      described_class.perform_now(place.id)

      expect(name_fetcher).to have_received(:call)
    end

    it 'can be enqueued' do
      expect { described_class.perform_later(place.id) }.to have_enqueued_job(described_class)
        .with(place.id)
        .on_queue('places')
    end
  end
end
