# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Point archive JSONB round trip' do
  let(:source_user) { create(:user) }
  let(:restored_user) { create(:user) }
  let(:geodata) { { 'properties' => { 'osm_id' => 12_345, 'name' => 'Synthetic Park' } } }
  let(:raw_data) { { 'device' => 'synthetic-device', 'nested' => { 'enabled' => true, 'values' => [1, 2] } } }

  def expect_json_objects(point)
    expect(point.geodata).to eq(geodata)
    expect(point.raw_data).to eq(raw_data)
    types = Point.where(id: point.id).pick(Arel.sql('jsonb_typeof(geodata), jsonb_typeof(raw_data)'))
    expect(types).to eq(%w[object object])
    osm_id = Point.where(id: point.id).pick(Arel.sql("geodata -> 'properties' ->> 'osm_id'"))
    expect(osm_id).to eq('12345')
  end

  it 'restores streamed JSONL from the real exporter as JSONB objects' do
    source_point = create(:point, user: source_user, geodata: geodata, raw_data: raw_data,
                                  reverse_geocoded_at: Time.utc(2025, 1, 1))
    Dir.mktmpdir('point-archive-roundtrip') do |directory|
      root = Pathname.new(directory)
      paths = Users::ExportData::Points.new(source_user, root.join('points')).call
      importer = Users::ImportData::Points.new(restored_user, batch_size: 1)
      paths.each do |path|
        File.foreach(root.join(path)) { |line| importer.add(Oj.load(line)) }
      end
      expect(importer.finalize).to eq(1)
    end

    restored = restored_user.points.sole
    expect_json_objects(restored)
    expect(restored.reverse_geocoded_at).to eq(source_point.reverse_geocoded_at)
  end

  it 'restores legacy in-memory exports as JSONB objects' do
    create(:point, user: source_user, geodata: geodata, raw_data: raw_data)
    data = Users::ExportData::Points.new(source_user).call

    expect(Users::ImportData::Points.new(restored_user, data).call).to eq(1)
    expect_json_objects(restored_user.points.sole)
  end

  it 'keeps already decoded objects intact' do
    data = [{ 'longitude' => 13.4, 'latitude' => 52.5, 'timestamp' => Time.utc(2025, 1, 1).to_i,
              'geodata' => geodata, 'raw_data' => raw_data }]

    expect(Users::ImportData::Points.new(restored_user, data).call).to eq(1)
    expect_json_objects(restored_user.points.sole)
  end

  it 'restores empty objects without making them candidates for raw-data archiving' do
    data = [{ 'longitude' => 13.4, 'latitude' => 52.5, 'timestamp' => Time.utc(2025, 1, 1).to_i,
              'geodata' => '{}', 'raw_data' => '{}' }]

    expect(Users::ImportData::Points.new(restored_user, data).call).to eq(1)
    expect(restored_user.points.sole.raw_data).to eq({})
    expect(restored_user.points.where("raw_data <> '{}'::jsonb")).not_to exist
  end
end
