# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Timeline coordinates for visits without a place', type: :request do
  let(:user) { create(:user) }
  let(:day) { Time.zone.parse('2026-09-04 00:00:00') }
  let!(:visit) do
    create(:visit, user: user, area: nil, place: nil, name: 'Unknown Location',
                   started_at: day + 12.hours, ended_at: day + 13.hours, duration: 60)
  end

  before do
    create(:point, user: user, visit: visit, latitude: 52.50, longitude: 13.40, timestamp: (day + 12.hours).to_i)
    create(:point, user: user, visit: visit, latitude: 52.52, longitude: 13.42, timestamp: (day + 13.hours).to_i)
    sign_in user
  end

  def assembler
    Timeline::DayAssembler.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601)
  end

  it 'carries the existing point-derived center without assigning a place' do
    entry = assembler.call.first[:entries].first
    expect(visit.reload.center).to match([be_within(1e-8).of(52.51), be_within(1e-8).of(13.41)])
    expect(entry[:center]).to match({ lat: be_within(1e-8).of(52.51), lng: be_within(1e-8).of(13.41) })
    expect(visit.reload.place_id).to be_nil
  end

  it 'renders coordinates and a place-search mount for an unlocated visit' do
    get map_timeline_feeds_path, params: { start_at: day.to_i, end_at: (day + 1.day).to_i }
    expect(response).to have_http_status(:ok)
    row = Nokogiri::HTML(response.body).at_css("#visit_entry_#{visit.id}")
    expect(row['data-visit-lat'].to_f).to be_within(1e-8).of(52.51)
    expect(row['data-visit-lng'].to_f).to be_within(1e-8).of(13.41)
    expect(row.at_css('[data-visit-place-search-target="mount"]')).to be_present
  end

  it 'keeps the location after a Turbo rename rebuilds the single row' do
    patch visit_path(visit), params: { visit: { name: 'My stop' } },
                            headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(response).to have_http_status(:ok)
    row = Nokogiri::HTML(response.body).at_css("#visit_entry_#{visit.id}")
    expect(row['data-visit-lat'].to_f).to be_within(1e-8).of(52.51)
    expect(row.at_css('[data-visit-place-search-target="mount"]')).to be_present
  end

  it 'does not invent coordinates at zero when no points exist' do
    visit.points.delete_all
    expect(assembler.build_visit_entry(visit)[:center]).to be_nil
  end

  it 'includes the point-derived location in day bounds' do
    expect(assembler.call.first[:bounds]).to match(
      sw_lat: be_within(1e-8).of(52.51), ne_lat: be_within(1e-8).of(52.51),
      sw_lng: be_within(1e-8).of(13.41), ne_lng: be_within(1e-8).of(13.41)
    )
  end

  it 'aggregates multiple unlocated visits without loading Point objects or growing the query count' do
    count_queries = lambda do
      queries = []
      record = lambda { |_name, _start, _finish, _id, payload|
        queries << payload[:sql] if payload[:sql].match?(/FROM "points"/i)
      }
      instantiated_points = 0
      record_objects = lambda do |_name, _start, _finish, _id, payload|
        instantiated_points += payload[:record_count] if payload[:class_name] == 'Point'
      end
      ActiveSupport::Notifications.subscribed(record_objects, 'instantiation.active_record') do
        ActiveSupport::Notifications.subscribed(record, 'sql.active_record') { assembler.call }
      end
      expect(instantiated_points).to eq(0)
      queries.size
    end
    one_visit_queries = count_queries.call
    5.times do |i|
      extra = create(:visit, user: user, place: nil, area: nil, started_at: day + i.hours,
                            ended_at: day + i.hours + 30.minutes, duration: 30)
      create(:point, user: user, visit: extra, latitude: 52.5, longitude: 13.4)
    end
    expect(count_queries.call).to eq(one_visit_queries)
    expect(assembler.call.first[:entries].map { |entry| entry[:center] }).to all(be_present)
  end

  it 'preserves real zero coordinates' do
    visit.points.update_all(lonlat: 'POINT(0 0)')
    expect(assembler.build_visit_entry(visit)[:center]).to eq({ lat: 0.0, lng: 0.0 })
  end

  it 'does not use a point belonging to another user even with an inconsistent visit association' do
    create(:point, visit: visit, latitude: 10, longitude: 20)
    expect(assembler.build_visit_entry(visit)[:center]).to match(
      { lat: be_within(1e-8).of(52.51), lng: be_within(1e-8).of(13.41) }
    )
  end

  it 'keeps the existing suggested-place coordinates ahead of GPS fallback' do
    suggestion = create(:place, user: user, latitude: 51, longitude: 12)
    visit.suggested_places << suggestion
    get map_timeline_feeds_path, params: { start_at: day.to_i, end_at: (day + 1.day).to_i }
    row = Nokogiri::HTML(response.body).at_css("#visit_entry_#{visit.id}")
    expect(row['data-visit-lat'].to_f).to eq(51)
    expect(row['data-visit-lng'].to_f).to eq(12)
  end
end
