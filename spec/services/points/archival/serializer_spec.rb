# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::Serializer do
  let(:user) { create(:user) }
  let!(:point) do
    create(:point, user:, longitude: 13.404954, latitude: 52.520008, timestamp: 1_700_000_000,
                   raw_data: { 'foo' => 'bar', 'n' => 42 })
  end

  it 'round-trips a point to a JSON line and back to identical attributes' do
    line = described_class.dump(Point.where(id: point.id).first)
    attrs = described_class.parse(line)

    expect(attrs['id']).to eq(point.id)
    expect(attrs['user_id']).to eq(user.id)
    expect(attrs['timestamp']).to eq(point.timestamp)
  end

  it 'preserves geometry exactly through dump/parse/insert' do
    line = described_class.dump(Point.where(id: point.id).first)
    attrs = described_class.parse(line)

    point.destroy!
    Point.connection.execute(described_class.insert_sql([attrs]))

    restored = Point.find(point.id)
    expect(restored.lonlat.x).to be_within(1e-9).of(13.404954)
    expect(restored.lonlat.y).to be_within(1e-9).of(52.520008)
  end

  it 'preserves jsonb columns exactly through dump/parse/insert' do
    line = described_class.dump(Point.where(id: point.id).first)
    attrs = described_class.parse(line)

    point.destroy!
    Point.connection.execute(described_class.insert_sql([attrs]))

    expect(Point.find(point.id).raw_data).to eq('foo' => 'bar', 'n' => 42)
  end

  it 'skips a row that collides on the lonlat/timestamp/user_id unique index' do
    line = described_class.dump(Point.where(id: point.id).first)
    attrs = described_class.parse(line)

    point.destroy!
    create(:point, user:, longitude: 13.404954, latitude: 52.520008, timestamp: 1_700_000_000)

    expect { Point.connection.execute(described_class.insert_sql([attrs])) }.not_to raise_error
  end

  it 'preserves text[] array columns exactly through dump/parse/insert' do
    point.update!(inrids: %w[zone1 zone2], in_regions: [])
    line = described_class.dump(Point.where(id: point.id).first)
    attrs = described_class.parse(line)

    point.destroy!
    Point.connection.execute(described_class.insert_sql([attrs]))

    restored = Point.find(point.id)
    expect(restored.inrids).to eq(%w[zone1 zone2])
    expect(restored.in_regions).to eq([])
  end
end
