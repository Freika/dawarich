# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit map coordinates without an attached place', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user) }
  let(:day) { Time.zone.parse('2026-09-04') }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
  let(:time_params) { { start_at: day.iso8601, end_at: (day + 1.day).iso8601 } }
  let!(:visit) do
    create(:visit, user: user, place: nil, area: nil, started_at: day + 12.hours,
                   ended_at: day + 13.hours, duration: 60)
  end

  before do
    create(:point, user: user, visit: visit, latitude: 52.50, longitude: 13.40, timestamp: (day + 12.hours).to_i)
    create(:point, user: user, visit: visit, latitude: 52.52, longitude: 13.42, timestamp: (day + 13.hours).to_i)
  end

  def expect_point_center(payload)
    expect(payload.fetch('place')).to include(
      'id' => nil, 'latitude' => be_within(1e-8).of(52.51), 'longitude' => be_within(1e-8).of(13.41)
    )
    expect(visit.reload.place_id).to be_nil
    expect(visit.area_id).to be_nil
  end

  it 'returns the GPS center for map markers without creating a place' do
    get '/api/v1/visits', params: time_params, headers: headers
    expect(response).to have_http_status(:ok)
    expect_point_center(response.parsed_body.find { |entry| entry['id'] == visit.id })
  end

  it 'returns the same center in visit details' do
    get "/api/v1/visits/#{visit.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect_point_center(response.parsed_body)
  end

  it 'preserves the coordinates in the response to a name update' do
    patch "/api/v1/visits/#{visit.id}", params: { visit: { name: 'My stop' } }, headers: headers
    expect(response).to have_http_status(:ok)
    expect_point_center(response.parsed_body)
  end

  it 'selects the displayed center, even when neither original point is inside the rectangle' do
    get '/api/v1/visits', params: time_params.merge(selection: 'true', sw_lat: 52.509, sw_lng: 13.409,
                                                    ne_lat: 52.511, ne_lng: 13.411), headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck('id')).to eq([visit.id])
    expect_point_center(response.parsed_body.first)
  end

  it 'does not select a visit merely because one of its points is inside the rectangle' do
    get '/api/v1/visits', params: time_params.merge(selection: 'true', sw_lat: 52.499, sw_lng: 13.399,
                                                    ne_lat: 52.501, ne_lng: 13.401), headers: headers
    expect(response.parsed_body).to eq([])
  end

  it 'keeps missing coordinates absent when the visit has no points' do
    visit.points.delete_all
    get "/api/v1/visits/#{visit.id}", headers: headers
    expect(response.parsed_body.fetch('place')).to eq('id' => nil, 'latitude' => nil, 'longitude' => nil)
  end

  it 'does not include a GPS-only visit outside the requested dates in a rectangle search' do
    get '/api/v1/visits', params: time_params.merge(start_at: (day + 2.days).iso8601,
                                                    end_at: (day + 3.days).iso8601, selection: 'true',
                                                    sw_lat: 52, sw_lng: 13, ne_lat: 53, ne_lng: 14), headers: headers
    expect(response.parsed_body).to eq([])
  end

  it 'keeps pagination totals and coordinates on the requested page' do
    create(:visit, user: user, place: nil, area: nil, started_at: day + 9.hours,
                   ended_at: day + 10.hours, duration: 60)
    get '/api/v1/visits', params: time_params.merge(page: 2, per_page: 1), headers: headers
    expect(response.headers['X-Total-Count']).to eq('2')
    expect(response.headers['X-Total-Pages']).to eq('2')
    expect(response.parsed_body.pluck('id')).to eq([visit.id])
    expect_point_center(response.parsed_body.first)
  end

  it 'batches map coordinates without instantiating Point objects or adding queries per visit' do
    5.times do |i|
      extra = create(:visit, user: user, place: nil, area: nil, started_at: day + i.hours,
                            ended_at: day + i.hours + 30.minutes, duration: 30)
      create(:point, user: user, visit: extra, latitude: 52.51, longitude: 13.41)
    end
    point_objects = 0
    aggregate_queries = 0
    objects = lambda do |_name, _start, _finish, _id, payload|
      point_objects += payload[:record_count] if payload[:class_name] == 'Point'
    end
    queries = lambda do |_name, _start, _finish, _id, payload|
      aggregate_queries += 1 if payload[:sql].include?('AVG(ST_Y')
    end
    ActiveSupport::Notifications.subscribed(objects, 'instantiation.active_record') do
      ActiveSupport::Notifications.subscribed(queries, 'sql.active_record') do
        get '/api/v1/visits', params: time_params, headers: headers
      end
    end
    expect(response.parsed_body.size).to eq(6)
    expect(response.parsed_body.map { |entry| entry['place']['latitude'] }).to all(be_within(1e-8).of(52.51))
    expect(aggregate_queries).to eq(1)
    expect(point_objects).to eq(0)
  end

  it 'preserves the strict rectangle boundary for a real zero-valued center' do
    visit.points.update_all(lonlat: 'POINT(0 0)')
    get '/api/v1/visits', params: time_params.merge(selection: 'true', sw_lat: 0, sw_lng: 0,
                                                    ne_lat: 1, ne_lng: 1), headers: headers
    expect(response.parsed_body).to eq([])
    get '/api/v1/visits', params: time_params.merge(selection: 'true', sw_lat: -1, sw_lng: -1,
                                                    ne_lat: 1, ne_lng: 1), headers: headers
    expect(response.parsed_body.first.fetch('place')).to eq('id' => nil, 'latitude' => 0.0, 'longitude' => 0.0)
  end

  it 'does not expose another users GPS-only visit in rectangle selection or details' do
    other = create(:visit, area: nil, place: nil, started_at: day + 12.hours, ended_at: day + 13.hours)
    create(:point, user: other.user, visit: other, latitude: 52.51, longitude: 13.41)
    get '/api/v1/visits', params: time_params.merge(selection: 'true', sw_lat: 52, sw_lng: 13,
                                                    ne_lat: 53, ne_lng: 14), headers: headers
    expect(response.parsed_body.pluck('id')).to eq([visit.id])
    get "/api/v1/visits/#{other.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'excludes points outside a restricted users visibility window from the center' do
    travel_to(day + 1.day) do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :lite)
      create(:point, user: user, visit: visit, latitude: 10, longitude: 20, timestamp: (day - 2.years).to_i)
      get "/api/v1/visits/#{visit.id}", headers: headers
      expect_point_center(response.parsed_body)
    end
  end
end
