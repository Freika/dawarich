# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::NameFetchingJob, type: :job do
  describe '#perform' do
    let(:place) { create(:place, name: Place::DEFAULT_NAME) }
    let(:name_fetcher) { instance_double(Places::NameFetcher) }

    before do
      allow(Places::NameFetcher).to receive(:new).with(place).and_return(name_fetcher)
      allow(name_fetcher).to receive(:call)
    end

    it 'finds the place and calls NameFetcher' do
      expect(Place).to receive(:find).with(place.id).and_return(place)
      expect(Places::NameFetcher).to receive(:new).with(place)
      expect(name_fetcher).to receive(:call)

      described_class.perform_now(place.id)
    end

    it 'can be enqueued' do
      expect { described_class.perform_later(place.id) }.to have_enqueued_job(described_class)
        .with(place.id)
        .on_queue('places')
    end
  end
end
