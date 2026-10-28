# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map range statistics', type: :request do
  let(:user) { create(:user) }
  let(:start_at) { Time.utc(2026, 7, 25, 18, 15).to_i }
  let(:end_at) { Time.utc(2026, 7, 26, 1).to_i }
  let(:params) { { start_at:, end_at: } }

  def point(seconds, longitude: 0, **attributes)
    create(:point, user:, timestamp: start_at + seconds, latitude: 0, longitude:,
                   lonlat: "POINT(#{longitude} 0)", **attributes)
  end

  def request_statistics(overrides = {})
    get '/api/v1/maps/statistics', params: params.merge(overrides),
                                   headers: { 'Authorization' => "Bearer #{user.api_key}" }
    response.parsed_body
  end

  it 'requires authentication' do
    get '/api/v1/maps/statistics', params: params
    expect(response).to have_http_status(:unauthorized)
  end

  it 'counts inclusive exact endpoints without including adjacent samples or another user' do
    point(-1, longitude: -1)
    point(0)
    point(end_at - start_at)
    point(end_at - start_at + 1, longitude: 1)
    create(:point, timestamp: start_at)
    expect(request_statistics).to eq('points' => 2, 'distance_meters' => 0.0)
  end

  it 'sums several routes, skips long gaps, anomalies and other trackers' do
    point(0)
    point(60, longitude: 0.01)
    point(7200, longitude: 10)
    point(7260, longitude: 10.01)
    point(30, longitude: 40, anomaly: true)
    point(30, longitude: 50, tracker_id: 'another-device')
    data = request_statistics
    expect(data['points']).to eq(5)
    expect(data['distance_meters']).to be_within(1).of(2226.39)
  end

  it 'keeps recorded track boundaries even when the points are only a minute apart' do
    first_track = create(:track, user:)
    second_track = create(:track, user:)
    point(0, track: first_track)
    point(60, longitude: 0.01, track: first_track)
    point(120, longitude: 10, track: second_track)
    point(180, longitude: 10.01, track: second_track)
    data = request_statistics
    expect(data['points']).to eq(4)
    expect(data['distance_meters']).to be_within(1).of(2226.39)
  end

  it 'does not include either edge crossing the selected time boundary' do
    point(-1, longitude: -10)
    point(0)
    point(60, longitude: 0.01)
    point(61, longitude: 10)
    data = request_statistics(end_at: start_at + 60)
    expect(data['points']).to eq(2)
    expect(data['distance_meters']).to be_within(1).of(1113.19)
  end

  it 'returns zero for an empty period and zero distance for a single point' do
    expect(request_statistics).to eq('points' => 0, 'distance_meters' => 0.0)
    point(0)
    expect(request_statistics).to eq('points' => 1, 'distance_meters' => 0.0)
  end

  it 'uses account timezone for local times, including a partial day across midnight' do
    user.update!(settings: user.settings.merge('timezone' => 'Europe/Berlin'))
    point(0)
    point(60)
    data = request_statistics(start_at: '2026-07-25T20:15', end_at: '2026-07-25T20:16')
    expect(data['points']).to eq(2)
  end

  it 'restricts the count and distance to the selected import owned by the user' do
    import = create(:import, user:)
    point(0, import:)
    point(60, longitude: 0.01, import:)
    point(120, longitude: 10)
    expect(request_statistics(import_id: import.id)['points']).to eq(2)
    expect(request_statistics(import_id: create(:import).id)['points']).to eq(0)
  end

  it 'does not bridge a privacy zone or disclose its points' do
    point(0)
    point(60, longitude: 1)
    point(120, longitude: 2)
    tag = create(:tag, :privacy_zone, user:, privacy_radius_meters: 100)
    place = create(:place, user:, latitude: 0, longitude: 1, lonlat: 'POINT(1 0)')
    create(:tagging, tag:, taggable: place)
    expect(request_statistics).to eq('points' => 2, 'distance_meters' => 0.0)
  end

  it 'applies the plan data window before counting and measuring' do
    point(0)
    point(60, longitude: 1)
    allow_any_instance_of(User).to receive(:scoped_points) { |account| account.points.where('timestamp > ?', start_at) }
    expect(request_statistics).to eq('points' => 1, 'distance_meters' => 0.0)
  end

  it 'enforces the real Lite window on Cloud' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update_column(:plan, User.plans[:lite])
    old = (DawarichSettings::LITE_DATA_WINDOW + 1.day).ago.to_i
    create(:point, user:, timestamp: old)
    create(:point, user:, timestamp: 1.hour.ago.to_i)
    data = request_statistics(start_at: old - 1, end_at: Time.current.to_i)
    expect(data).to eq('points' => 1, 'distance_meters' => 0.0)
  end

  it 'rejects missing, invalid and reversed ranges' do
    [nil, 'nonsense', end_at + 1].each do |invalid|
      request_statistics(start_at: invalid)
      expect(response).to have_http_status(:bad_request)
    end
  end

  it 'invalidates cached totals after source points change' do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    point(0)
    moving = point(60, longitude: 0.01)
    expect(request_statistics['points']).to eq(2)
    user.points.where(id: moving.id).update_all(lonlat: 'POINT(0.02 0)')
    data = request_statistics
    expect(data['distance_meters']).to be_within(1).of(2226.39)
    user.points.where(id: moving.id).delete_all
    expect(request_statistics).to eq('points' => 1, 'distance_meters' => 0.0)
  end

  it 'reports timeouts without returning misleading zero totals' do
    allow_any_instance_of(Maps::RangeStatistics).to receive(:call).and_raise(ActiveRecord::QueryCanceled)
    request_statistics
    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers['Cache-Control']).to include('no-store')
  end
end
