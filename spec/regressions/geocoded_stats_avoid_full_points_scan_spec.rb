# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Counting geocoded points for a dominant user' do
  def plan_nodes(node)
    [node] + node.fetch('Plans', []).flat_map { |child| plan_nodes(child) }
  end

  it 'returns the correct count without a full sequential scan of points' do
    user = create(:user)
    other_user = create(:user)
    now = Time.current
    geocoded_count = 20_000

    # Bulk synthetic fixtures avoid geocoder callbacks. The coordinates are
    # invented points in the open South Pacific; no location data is imported.
    rows = Array.new(geocoded_count) do |index|
      {
        user_id: user.id,
        timestamp: 1_700_000_000 + index,
        lonlat: 'POINT(-140.123 -50.456)',
        reverse_geocoded_at: now,
        raw_data: { 'synthetic_padding' => 'x' * 256 },
        created_at: now,
        updated_at: now
      }
    end
    rows << rows.first.merge(timestamp: 1_699_999_999, reverse_geocoded_at: nil)
    4.times do |index|
      rows << rows.first.merge(user_id: other_user.id, timestamp: 1_600_000_000 + index)
    end
    Point.insert_all!(rows)
    user.update!(points_count: geocoded_count + 1)
    other_user.update!(points_count: 4)

    connection = Point.connection
    connection.execute('SET LOCAL random_page_cost = 4')
    connection.execute('SET LOCAL seq_page_cost = 1')
    connection.execute('ANALYZE points')

    count_queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      count_queries << sql if sql.match?(/SELECT COUNT\(\*\) FROM points/i)
    end

    stats = ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
        StatsQuery.new(user).cached_points_geocoded_stats
      end
    end

    expect(stats).to eq(geocoded: geocoded_count, without_data: geocoded_count)

    # Isolate the geocoded total. The separate without-data count has additional
    # filters and is another scan, outside this regression's scope.
    geocoded_queries = count_queries.reject { |sql| sql.match?(/\bcity\b/i) }
    full_scans = geocoded_queries.flat_map do |sql|
      plan = JSON.parse(connection.select_value("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{sql}"))
      plan_nodes(plan.first.fetch('Plan')).select do |node|
        node['Relation Name'] == 'points' && node['Node Type'].include?('Seq Scan')
      end
    end

    expect(full_scans).to be_empty,
                          "geocoded total reads the full points heap: #{full_scans.to_json}"
  end

  it 'never reports a negative count while the point counter runs behind' do
    user = create(:user)
    create(:point, user:).update_columns(reverse_geocoded_at: nil)
    create(:point, user:).update_columns(reverse_geocoded_at: nil)
    user.update_column(:points_count, 1)

    expect(StatsQuery.new(user).cached_points_geocoded_stats[:geocoded]).to eq(0)
  end
end
