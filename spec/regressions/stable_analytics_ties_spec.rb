# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Stable analytics tie ordering' do
  let(:user) { create(:user) }

  it 'picks the same dominant mode regardless of segment enumeration' do
    track = create(:track, user: user)
    first = create(:track_segment, track: track, transportation_mode: :walking, distance: 100, duration: 100)
    second = create(:track_segment, track: track, transportation_mode: :driving, distance: 100, duration: 100)

    expect(Track.pick_dominant_mode([second, first])).to eq(Track.pick_dominant_mode([first, second]))
  end

  [InsightsController, Api::V1::InsightsController].each do |controller_class|
    it "orders tied visits before selecting the top five in #{controller_class}" do
      area = create(:area, user: user)
      %w[Zulu Echo Delta Charlie Bravo Alpha].each do |name|
        create(:visit, user: user, area: area, name: name, status: :confirmed,
                       started_at: Time.utc(2026, 4, 1), ended_at: Time.utc(2026, 4, 1, 1), duration: 3600)
      end
      Point.connection.execute('SET LOCAL enable_sort = off')
      controller = controller_class.new
      allow(controller).to receive(controller_class == InsightsController ? :current_user : :current_api_user)
        .and_return(user)
      controller.instance_variable_set(:@selected_year, 2026)

      expect(controller.send(:fetch_yearly_top_visits).map { |visit| visit[:name] })
        .to eq(%w[Alpha Bravo Charlie Delta Echo])
    end
  end

  it 'orders tied digest country durations lexically' do
    calculator = Users::Digests::CalculateYear.new(user.id, 2026)

    expect(calculator.send(:format_top_countries, { 'Germany' => 60, 'France' => 60 }).map { |item| item['name'] })
      .to eq(%w[France Germany])
  end

  it 'orders tied residency counts lexically regardless of query enumeration' do
    counter = Residency::DayCounter.new(user, 2026)
    rows = %w[Germany France].map do |country|
      { 'point_date' => '2026-04-01', 'country_name' => country, 'point_count' => 1 }
    end
    allow(counter).to receive(:daily_country_counts).and_return(rows)

    expect(counter.call[:daily_countries]['2026-04-01']).to eq('France')
    expect(counter.call[:countries].map { |country| country[:country_name] }).to eq(%w[France Germany])
  end

  it 'picks the same representative coordinates when timestamp and accuracy tie' do
    points = [2, 1].map do |id|
      { id: id, timestamp: 1_775_001_600, accuracy: 10, coordinates: [52.0, id.to_f],
        distance_meters: 1.0, date: '2026-04-01T00:00:00Z', city: 'Berlin', country: 'Germany', altitude: nil }
    end
    aggregator = LocationSearch::ResultAggregator.new

    expect(aggregator.group_points_into_visits(points).first[:coordinates])
      .to eq(aggregator.group_points_into_visits(points.reverse).first[:coordinates])
  end

  it 'uses point IDs to break Immich GPS timestamp ties across query plans' do
    older = create(:point, user: user, timestamp: Time.utc(2026, 4, 1).to_i, lonlat: 'POINT(13 52)')
    newer = create(:point, user: user, timestamp: older.timestamp, lonlat: 'POINT(14 53)')
    photo = { 'id' => 'synthetic-photo', 'fileCreatedAt' => Time.utc(2026, 4, 1).iso8601 }
    scan = Immich::EnrichScan.new(user)
    original = Point.connection.select_value('SHOW enable_sort')
    begin
      Point.connection.execute('SET LOCAL enable_sort = off')
      first = scan.send(:match_photos_to_points, [photo]).first
      Point.connection.execute('SET LOCAL enable_sort = on')
      second = scan.send(:match_photos_to_points, [photo]).first
      expect(first).to eq(second)
      expect(first[:longitude]).to eq(newer.lon)
    ensure
      Point.connection.execute("SET LOCAL enable_sort = #{original}")
    end
  end
end
