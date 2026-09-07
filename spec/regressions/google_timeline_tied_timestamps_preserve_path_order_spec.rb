# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Google Timeline tied timestamps preserve path order' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, name: 'phone_takeout.json') }

  def import_json(data)
    file = Tempfile.new(['phone_takeout_tied', '.json'])
    file.write(data.to_json)
    file.rewind
    GoogleMaps::PhoneTakeoutImporter.new(import, user.id, file.path).call
  ensure
    file.close!
  end

  context 'when a semantic timelinePath has distinct coordinates sharing a source timestamp' do
    let(:data) do
      {
        'semanticSegments' => [
          {
            'startTime' => '2024-06-15T10:00:00.000Z',
            'endTime' => '2024-06-15T11:00:00.000Z',
            'timelinePath' => [
              { 'point' => 'geo:48.8600,2.3400', 'time' => '2024-06-15T10:05:00.000Z' },
              { 'point' => 'geo:48.8610,2.3410', 'time' => '2024-06-15T10:05:00.000Z' },
              { 'point' => 'geo:48.8620,2.3420', 'time' => '2024-06-15T10:05:00.000Z' }
            ]
          }
        ]
      }
    end

    it 'assigns consecutive one-second offsets in path order' do
      import_json(data)

      base = DateTime.parse('2024-06-15T10:05:00.000Z').utc.to_i
      points = user.points.order(:timestamp)

      expect(points.map(&:timestamp)).to eq([base, base + 1, base + 2])
      expect(points.map { |point| [point.lat.round(4), point.lon.round(4)] })
        .to eq([[48.86, 2.34], [48.861, 2.341], [48.862, 2.342]])
    end
  end

  context 'when a semantic timelinePath repeats an exact coordinate between tied points' do
    let(:data) do
      {
        'semanticSegments' => [
          {
            'startTime' => '2024-06-15T10:00:00.000Z',
            'endTime' => '2024-06-15T11:00:00.000Z',
            'timelinePath' => [
              { 'point' => 'geo:48.8600,2.3400', 'time' => '2024-06-15T10:05:00.000Z' },
              { 'point' => 'geo:48.8610,2.3410', 'time' => '2024-06-15T10:05:00.000Z' },
              { 'point' => 'geo:48.8600,2.3400', 'time' => '2024-06-15T10:05:00.000Z' }
            ]
          }
        ]
      }
    end

    it 'reuses the assigned timestamp so the repeat collapses instead of shifting' do
      import_json(data)

      base = DateTime.parse('2024-06-15T10:05:00.000Z').utc.to_i
      points = user.points.order(:timestamp)

      expect(points.map(&:timestamp)).to eq([base, base + 1])
      expect(points.map { |point| [point.lat.round(4), point.lon.round(4)] })
        .to eq([[48.86, 2.34], [48.861, 2.341]])
    end
  end

  context 'when a raw-array timelinePath has distinct coordinates sharing a duration offset' do
    let(:data) do
      [
        {
          'startTime' => '2024-06-15T10:00:00.000Z',
          'endTime' => '2024-06-15T11:00:00.000Z',
          'timelinePath' => [
            { 'point' => 'geo:48.8600,2.3400', 'durationMinutesOffsetFromStartTime' => '5' },
            { 'point' => 'geo:48.8610,2.3410', 'durationMinutesOffsetFromStartTime' => '5' },
            { 'point' => 'geo:48.8620,2.3420', 'durationMinutesOffsetFromStartTime' => '5' }
          ]
        }
      ]
    end

    it 'assigns consecutive one-second offsets in path order' do
      import_json(data)

      base = DateTime.parse('2024-06-15T10:05:00.000Z').utc.to_i
      points = user.points.order(:timestamp)

      expect(points.map(&:timestamp)).to eq([base, base + 1, base + 2])
      expect(points.map { |point| [point.lat.round(4), point.lon.round(4)] })
        .to eq([[48.86, 2.34], [48.861, 2.341], [48.862, 2.342]])
    end
  end

  context 'when a raw-array timelinePath repeats an exact coordinate between tied points' do
    let(:data) do
      [
        {
          'startTime' => '2024-06-15T10:00:00.000Z',
          'endTime' => '2024-06-15T11:00:00.000Z',
          'timelinePath' => [
            { 'point' => 'geo:48.8600,2.3400', 'durationMinutesOffsetFromStartTime' => '5' },
            { 'point' => 'geo:48.8610,2.3410', 'durationMinutesOffsetFromStartTime' => '5' },
            { 'point' => 'geo:48.8600,2.3400', 'durationMinutesOffsetFromStartTime' => '5' }
          ]
        }
      ]
    end

    it 'reuses the assigned timestamp so the repeat collapses instead of shifting' do
      import_json(data)

      base = DateTime.parse('2024-06-15T10:05:00.000Z').utc.to_i
      points = user.points.order(:timestamp)

      expect(points.map(&:timestamp)).to eq([base, base + 1])
      expect(points.map { |point| [point.lat.round(4), point.lon.round(4)] })
        .to eq([[48.86, 2.34], [48.861, 2.341]])
    end
  end

  context 'when more tied points share a source timestamp than fit within its minute' do
    let(:data) do
      path = (0...62).map do |index|
        { 'point' => "geo:48.#{format('%06d', 860_000 + index)},2.340000", 'time' => '2024-06-15T10:05:00.000Z' }
      end

      { 'semanticSegments' => [{ 'startTime' => '2024-06-15T10:00:00.000Z', 'timelinePath' => path }] }
    end

    it 'clamps synthetic offsets so they never cross into the next minute' do
      import_json(data)

      base = DateTime.parse('2024-06-15T10:05:00.000Z').utc.to_i
      timestamps = user.points.pluck(:timestamp)

      expect(timestamps.count).to eq(62)
      expect(timestamps.min).to eq(base)
      expect(timestamps.max).to eq(base + 59)
    end
  end

  context 'when two semantic tie groups have sub-minute source timestamps' do
    let(:data) do
      path_a = (0...10).map do |i|
        { 'point' => "geo:48.#{860 + i},2.#{340 + i}", 'time' => '2024-06-15T10:05:23.000Z' }
      end
      path_b = (0...2).map do |i|
        { 'point' => "geo:48.#{870 + i},2.#{350 + i}", 'time' => '2024-06-15T10:05:28.000Z' }
      end
      { 'semanticSegments' => [{
        'startTime' => '2024-06-15T10:00:00.000Z',
        'endTime' => '2024-06-15T11:00:00.000Z',
        'timelinePath' => path_a + path_b
      }] }
    end

    it 'preserves distinct timestamps and path order across adjacent tie groups' do
      import_json(data)

      base = DateTime.parse('2024-06-15T10:05:23.000Z').utc.to_i
      points = user.points.order(:timestamp)

      expect(points.map(&:timestamp)).to eq((base..base + 11).to_a)
      expect(points.map { |point| [point.lat.round(4), point.lon.round(4)] })
        .to eq(
          (0...10).map { |i| [(48.86 + i * 0.001).round(4), (2.34 + i * 0.001).round(4)] } +
          (0...2).map  { |i| [(48.87 + i * 0.001).round(4), (2.35 + i * 0.001).round(4)] }
        )
    end
  end

  context 'when adjacent tie groups collide on both timestamp and coordinates' do
    let(:data) do
      path_a = (0...6).map do |i|
        { 'point' => "geo:48.#{format('%06d', 860_000 + i * 20)},2.#{format('%06d', 340_000 + i * 20)}",
          'time'  => '2024-06-15T10:05:23.000Z' }
      end
      path_b = [
        { 'point' => 'geo:48.860100,2.340100',
          'time'  => '2024-06-15T10:05:28.000Z' }
      ]
      { 'semanticSegments' => [{
        'startTime' => '2024-06-15T10:00:00.000Z',
        'endTime' => '2024-06-15T11:00:00.000Z',
        'timelinePath' => path_a + path_b
      }] }
    end

    it 'does not silently drop the later point' do
      import_json(data)

      expect(user.points.count).to eq(7)
    end

    it 'stores the later point past the previous group last assigned timestamp' do
      import_json(data)

      base = DateTime.parse('2024-06-15T10:05:23.000Z').utc.to_i
      points_at_coord = user.points.where(lonlat: 'POINT(2.3401 48.8601)').order(:timestamp)

      expect(points_at_coord.map(&:timestamp)).to eq([base + 5, base + 6])
    end
  end

  context 'when a new tie group source timestamp exceeds the MAX_TIE_OFFSET collision range' do
    let(:data) do
      path_a = (0...62).map do |i|
        { 'point' => "geo:48.#{format('%06d', 860_000 + i)},2.#{format('%06d', 340_000 + i)}",
          'time'  => '2024-06-15T10:05:00.000Z' }
      end
      path_b = (0...3).map do |i|
        { 'point' => "geo:49.#{format('%06d', 100_000 + i)},3.#{format('%06d', 100_000 + i)}",
          'time'  => '2024-06-15T10:05:01.000Z' }
      end
      { 'semanticSegments' => [{
        'startTime' => '2024-06-15T10:00:00.000Z',
        'endTime' => '2024-06-15T11:00:00.000Z',
        'timelinePath' => path_a + path_b
      }] }
    end

    it 'clamps the cross-group push so group B is pushed past the previous group without exceeding MAX_TIE_OFFSET' do
      import_json(data)

      base = DateTime.parse('2024-06-15T10:05:00.000Z').utc.to_i
      timestamps = user.points.pluck(:timestamp)

      expect(timestamps.count).to eq(65)
      expect(timestamps.max).to eq(base + 60)
      expect(timestamps.count(base + 59)).to eq(3)
      expect(timestamps.count(base + 60)).to eq(3)
    end
  end

  context 'when a lone point follows a tie group with sub-minute spacing' do
    let(:data) do
      path_a = [
        { 'point' => 'geo:48.8600,2.3400', 'time' => '2024-06-15T10:05:23.000Z' },
        { 'point' => 'geo:48.8610,2.3410', 'time' => '2024-06-15T10:05:23.000Z' },
        { 'point' => 'geo:48.8620,2.3420', 'time' => '2024-06-15T10:05:23.000Z' }
      ]
      path_b = [
        { 'point' => 'geo:48.8630,2.3430', 'time' => '2024-06-15T10:05:25.000Z' }
      ]
      { 'semanticSegments' => [{
        'startTime' => '2024-06-15T10:00:00.000Z',
        'endTime' => '2024-06-15T11:00:00.000Z',
        'timelinePath' => path_a + path_b
      }] }
    end

    it 'pushes the lone point past the previous group last assigned timestamp' do
      import_json(data)

      base = DateTime.parse('2024-06-15T10:05:23.000Z').utc.to_i
      points = user.points.order(:timestamp)

      expect(points.map(&:timestamp)).to eq([base, base + 1, base + 2, base + 3])
    end
  end
end
