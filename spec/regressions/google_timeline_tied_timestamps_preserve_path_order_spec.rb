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
end
