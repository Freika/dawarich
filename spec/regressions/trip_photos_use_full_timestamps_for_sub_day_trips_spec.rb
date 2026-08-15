# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip photos use full timestamps when searching for assets' do
  let(:user) { instance_double('User') }

  before do
    allow(user).to receive(:immich_integration_configured?).and_return(true)
    allow(user).to receive(:photoprism_integration_configured?).and_return(false)
    allow(user).to receive(:api_key).and_return('test-api-key')
  end

  context 'when a trip spans hours within a single day' do
    let(:started_at) { Time.utc(2024, 3, 29, 8, 0, 0) }
    let(:ended_at)   { Time.utc(2024, 3, 29, 20, 0, 0) }
    let(:trip)       { instance_double('Trip', started_at: started_at, ended_at: ended_at) }

    it 'passes distinct ISO8601 datetime bounds to Photos::Search' do
      photo_search = instance_double('Photos::Search', call: [])

      expect(Photos::Search).to receive(:new) do |received_user, **kwargs|
        expect(received_user).to eq(user)
        expect(kwargs[:start_date]).to eq('2024-03-29T08:00:00Z')
        expect(kwargs[:end_date]).to   eq('2024-03-29T20:00:00Z')
        expect(kwargs[:start_date]).not_to eq(kwargs[:end_date]),
                                           'sub-day trip bounds collapsed to the same value; downstream Immich/Photoprism ' \
                                           'filtering will reject every photo because takenAfter == takenBefore'
        photo_search
      end

      Trips::Photos.new(trip, user).call
    end
  end

  context 'when a trip spans multiple days' do
    let(:started_at) { Time.utc(2024, 3, 29, 8, 0, 0) }
    let(:ended_at)   { Time.utc(2024, 4, 2, 20, 0, 0) }
    let(:trip)       { instance_double('Trip', started_at: started_at, ended_at: ended_at) }

    it 'still passes ISO8601 datetime bounds (no date-only truncation)' do
      photo_search = instance_double('Photos::Search', call: [])

      expect(Photos::Search).to receive(:new) do |_received_user, **kwargs|
        expect(kwargs[:start_date]).to eq('2024-03-29T08:00:00Z')
        expect(kwargs[:end_date]).to   eq('2024-04-02T20:00:00Z')
        photo_search
      end

      Trips::Photos.new(trip, user).call
    end
  end
end
