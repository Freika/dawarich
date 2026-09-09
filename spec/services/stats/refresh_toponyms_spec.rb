# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::RefreshToponyms do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC', 'min_minutes_spent_in_city' => 0 }) }
  let!(:stat) do
    create(:stat, user: user, year: 2014, month: 6, toponyms: [], distance: 123,
                  daily_distance: { '15' => 123 }, h3_hex_ids: [['hex', 12]], calculation_version: 1)
  end
  let!(:point) do
    create(:point, user: user, timestamp: Time.utc(2014, 6, 15, 12).to_i,
                   city: 'Berlin', country: 'Germany', velocity: 0)
  end

  it 'repairs countries and cities without changing distance, coverage, sharing or calculation version' do
    before = stat.attributes.except('toponyms', 'updated_at')
    described_class.new(user, 2014, 6).call
    expect(stat.reload.toponyms.first['country']).to eq('Germany')
    expect(stat.toponyms.first['cities'].first['city']).to eq('Berlin')
    expect(stat.attributes.except('toponyms', 'updated_at')).to eq(before)
  end

  it 'does not rewrite an unchanged result' do
    described_class.new(user, 2014, 6).call
    before = stat.reload.updated_at
    travel 1.hour do
      described_class.new(user, 2014, 6).call
      expect(stat.reload.updated_at).to eq(before)
    end
  end

  it 'repairs a partial nonempty result' do
    stat.update!(toponyms: [{ country: 'France', cities: [] }])
    described_class.new(user, 2014, 6).call
    expect(stat.reload.toponyms.map { |row| row['country'] }).to eq(['Germany'])
  end

  it 'does not load H3, coordinates or raw point payloads' do
    statements = []
    ActiveSupport::Notifications.subscribed(->(*args) { statements << args.last[:sql] }, 'sql.active_record') do
      described_class.new(user, 2014, 6).call
    end
    reads = statements.grep(/SELECT.*FROM "(?:points|stats)"/)
    expect(reads).not_to be_empty
    expect(reads.join).not_to match(/h3_hex_ids|lonlat|raw_data|"(?:points|stats)"\.\*/)
    expect(stat.reload.toponyms).not_to be_empty
  end

  it 'does not create an incomplete stats row for a missing month' do
    point.update!(timestamp: Time.utc(2015, 1, 15).to_i)
    expect(described_class.new(user, 2015, 1).call).to be(false)
    expect(user.stats.where(year: 2015, month: 1)).not_to exist
  end

  it 'uses local month boundaries across the year boundary' do
    user.update!(settings: { 'timezone' => 'Asia/Tokyo', 'min_minutes_spent_in_city' => 0 })
    point.update!(timestamp: Time.utc(2014, 12, 31, 23, 30).to_i)
    january = create(:stat, user: user, year: 2015, month: 1, toponyms: [])
    described_class.new(user, 2014, 6).call
    described_class.new(user, 2015, 1).call
    expect(stat.reload.toponyms).to be_empty
    expect(january.reload.toponyms.first['country']).to eq('Germany')
  end
  it 'consumes every cursor batch even when the ActiveRecord query cache is enabled' do
    start = Time.utc(2014, 6, 1).to_i
    Point.insert_all!(4001.times.map do |id|
      { user_id: user.id, timestamp: start + id, lonlat: 'POINT(13.4 52.5)', city: 'Berlin',
        country_name: 'Germany', velocity: '0', anomaly: false, created_at: Time.current, updated_at: Time.current }
    end)
    Point.cache { described_class.new(user, 2014, 6).call }
    expect(stat.reload.toponyms.first['cities'].first['points']).to eq(4002)
  end
end
