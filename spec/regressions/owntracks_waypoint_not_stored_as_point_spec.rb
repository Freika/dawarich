# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OwnTracks waypoint payloads are not stored as location points', type: :request do
  let(:user) { create(:user) }

  def post_owntracks(payload)
    post "/api/v1/owntracks/points?api_key=#{user.api_key}", params: payload
  end

  it 'ignores _type=waypoint config-sync payloads even when they carry coordinates' do
    waypoint = { _type: 'waypoint', desc: 'Home', lat: 52.232, lon: 13.339, rad: 50, tst: 1_717_459_768 }

    expect { post_owntracks(waypoint) }.not_to(change(Point, :count))
    expect(response).to have_http_status(:ok)
  end

  it 'still stores _type=location fixes' do
    location = { _type: 'location', lat: 52.225, lon: 13.332, tst: 1_709_283_789, tid: 'RO', topic: 'owntracks/u/d' }

    expect { post_owntracks(location) }.to change(Point, :count).by(1)
  end
end
