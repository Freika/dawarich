# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::Photos do
  let(:user) { instance_double('User') }
  let(:started_at) { Time.utc(2024, 1, 1, 10, 0, 0) }
  let(:ended_at) { Time.utc(2024, 1, 7, 18, 30, 0) }
  let(:trip) { instance_double('Trip', started_at: started_at, ended_at: ended_at) }
  let(:service) { described_class.new(trip, user) }

  describe '#call' do
    context 'when user has no photo integrations configured' do
      before do
        allow(user).to receive(:immich_integration_configured?).and_return(false)
        allow(user).to receive(:photoprism_integration_configured?).and_return(false)
      end

      it 'returns an empty array' do
        expect(service.call).to eq([])
      end
    end

    context 'when user has photo integrations configured' do
      let(:photo_search) { instance_double('Photos::Search') }
      let(:raw_photos) do
        [
          {
            id: 1,
            source: 'immich',
            orientation: 'landscape',
            localDateTime: '2024-01-02T14:30:00',
            capturedAt: '2024-01-02T13:30:00Z'
          },
          {
            id: 2,
            source: 'photoprism',
            orientation: 'portrait',
            localDateTime: '2024-01-03T09:00:00',
            capturedAt: '2024-01-03T08:00:00Z'
          }
        ]
      end

      before do
        allow(user).to receive(:immich_integration_configured?).and_return(true)
        allow(user).to receive(:photoprism_integration_configured?).and_return(false)
        allow(user).to receive(:api_key).and_return('test-api-key')

        allow(Photos::Search).to receive(:new)
          .with(user, start_date: '2024-01-01T10:00:00Z', end_date: '2024-01-07T18:30:00Z')
          .and_return(photo_search)
        allow(photo_search).to receive(:call).and_return(raw_photos)
      end

      it 'returns formatted photo thumbnails' do
        expected_result = [
          {
            id: 1,
            url: '/api/v1/photos/1/thumbnail.jpg?api_key=test-api-key&source=immich',
            source: 'immich',
            orientation: 'landscape',
            taken_at: '2024-01-02T13:30:00Z'
          },
          {
            id: 2,
            url: '/api/v1/photos/2/thumbnail.jpg?api_key=test-api-key&source=photoprism',
            source: 'photoprism',
            orientation: 'portrait',
            taken_at: '2024-01-03T08:00:00Z'
          }
        ]

        expect(service.call).to eq(expected_result)
      end
    end
  end
end
