# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Geofence evaluation on point ingest', type: :request do
  let(:user) { create(:user) }
  let!(:area) { create(:area, user:, latitude: 52.52, longitude: 13.405, radius: 100) }
  let(:time) { 5.minutes.ago.utc.change(usec: 0) }
  let(:feature) do
    { type: 'Feature', geometry: { type: 'Point', coordinates: [13.405, 52.52] },
      properties: { timestamp: time.iso8601, horizontal_accuracy: 10 } }
  end

  before { GeofenceEvents::StateStore.new(user).reset! }

  def enters
    GeofenceEvent.where(user:, area:, source: :server_inferred).event_type_enter
  end

  it 'evaluates points from the points API' do
    post "/api/v1/points?api_key=#{user.api_key}", params: { locations: [feature] }, as: :json

    expect(enters.count).to eq(1)
  end

  it 'evaluates OwnTracks points' do
    post "/api/v1/owntracks/points?api_key=#{user.api_key}",
         params: { _type: 'location', lat: 52.52, lon: 13.405, tst: time.to_i, acc: 10 }, as: :json

    expect(enters.count).to eq(1)
  end

  it 'evaluates Overland batches' do
    post "/api/v1/overland/batches?api_key=#{user.api_key}", params: { locations: [feature] }, as: :json

    expect(enters.count).to eq(1)
  end

  it 'evaluates Traccar points' do
    post "/api/v1/traccar/points?api_key=#{user.api_key}",
         params: { device_id: 'phone',
                   location: { timestamp: time.iso8601, latitude: 52.52, longitude: 13.405, accuracy: 10 } },
         as: :json

    expect(enters.count).to eq(1)
  end
end
