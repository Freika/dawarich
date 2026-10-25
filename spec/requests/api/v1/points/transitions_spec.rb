# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/points/transitions', type: :request do
  let(:user) { create(:user) }
  let(:place) { create(:place, :geofence, user:) }
  let(:params) do
    { place_id: place.id, event_type: 'enter', occurred_at: 1.minute.ago.iso8601, lonlat: [13.539, 52.437],
      accuracy_m: 12, device_id: 'phone-1', metadata: { battery: 0.7, os: 'ios-18' } }
  end

  before { GeofenceEvents::StateStore.new(user).reset! }

  def post_transition(overrides = {}, api_key: user.api_key)
    post '/api/v1/points/transitions', params: params.merge(overrides),
                                       headers: { 'Authorization' => "Bearer #{api_key}" }, as: :json
  end

  it 'records a transition reported by the phone' do
    post_transition

    expect(response).to have_http_status(:created)
    expect(GeofenceEvent.sole).to have_attributes(
      source: 'native_app', event_type: 'enter', accuracy_m: 12, device_id: 'phone-1',
      metadata: { 'battery' => 0.7, 'os' => 'ios-18' }
    )
  end

  it 'accepts transitions from a Lite user on cloud' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update!(plan: :lite)

    post_transition

    expect(response).to have_http_status(:created)
  end

  it 'answers 204 for a place of someone else or one that does not notify' do
    post_transition({ place_id: create(:place, :geofence).id })
    expect(response).to have_http_status(:no_content)

    post_transition({ place_id: create(:place, user:).id })
    expect(response).to have_http_status(:no_content)

    expect(GeofenceEvent.count).to eq(0)
  end

  it 'rejects malformed transitions' do
    [
      { event_type: 'linger' },
      { lonlat: [200, 52] },
      { lonlat: ['x', 52] },
      { lonlat: [13] },
      { occurred_at: 10.minutes.from_now.iso8601 },
      { occurred_at: 25.hours.ago.iso8601 },
      { occurred_at: 'yesterday' },
      { device_id: 'x' * 256 },
      { metadata: { nested: { deep: 1 } } },
      { metadata: (1..21).index_by { |i| "k#{i}" } },
      { metadata: { note: 'x' * 3_000 } }
    ].each do |override|
      post_transition(override)

      expect(response).to have_http_status(:unprocessable_content), "accepted #{override.inspect}"
    end
    expect(GeofenceEvent.count).to eq(0)
  end

  it 'rounds a fractional accuracy and treats a negative one as unknown' do
    post_transition({ accuracy_m: 8.6 })
    post_transition({ event_type: 'leave', accuracy_m: -1 })

    expect(GeofenceEvent.order(:id).pluck(:accuracy_m)).to eq([9, nil])
  end

  it 'requires an api key' do
    post_transition({}, api_key: 'nope')

    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not move state for a transition older than the latest evaluated point' do
    GeofenceEvents::StateStore.new(user).advance_evaluated_at!(Time.current.to_i)

    post_transition({ occurred_at: 10.minutes.ago.iso8601 })

    expect(response).to have_http_status(:created)
    expect(GeofenceEvents::StateStore.new(user).inside_ids).to be_empty
  end
end
