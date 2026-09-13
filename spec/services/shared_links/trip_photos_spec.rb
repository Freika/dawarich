# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLinks::TripPhotos do
  let(:owner) { create(:user) }
  let(:trip) do
    create(:trip, user: owner, started_at: Time.utc(2024, 11, 27), ended_at: Time.utc(2024, 11, 30))
  end
  let(:link) do
    create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                         settings: { 'show_photos' => true })
  end
  let(:found_photos) do
    [
      { id: 'p1', source: 'immich', latitude: 52.0, longitude: 13.0,
        capturedAt: '2024-11-27T23:30:00Z', localDateTime: '2024-11-28T00:30:00' },
      { id: 'p2', source: 'immich', latitude: 60.0, longitude: 10.0,
        capturedAt: '2024-11-29T08:00:00Z', localDateTime: '2024-11-29T09:00:00' }
    ]
  end

  before do
    allow(Photos::Search).to receive(:new).and_return(instance_double(Photos::Search, call: found_photos))
  end

  it 'groups trip photos by their day in the given timezone' do
    result = described_class.new(link, timezone: 'Europe/Berlin').call

    expect(result.keys).to contain_exactly(Date.new(2024, 11, 28), Date.new(2024, 11, 29))
    expect(result[Date.new(2024, 11, 28)].map { _1[:id] }).to eq(['p1'])
    expect(result[Date.new(2024, 11, 28)].first).to include(source: 'immich', taken_at: '2024-11-27T23:30:00Z')
  end

  it 'excludes photos inside a privacy zone' do
    home = create(:place, user: owner, latitude: 52.0, longitude: 13.0)
    tag = create(:tag, user: owner, privacy_radius_meters: 500)
    create(:tagging, tag: tag, taggable: home)

    result = described_class.new(link, timezone: 'Europe/Berlin').call

    expect(result.values.flatten.map { _1[:id] }).to eq(['p2'])
  end
end
