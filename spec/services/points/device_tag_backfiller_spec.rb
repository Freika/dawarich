# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::DeviceTagBackfiller do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_records, name: 'Records.json') }

  # Two devices reporting in the same window: the phone that travelled and a
  # device left behind. Google keeps both in one Records.json, which is exactly
  # why their points end up sharing a tracker_id.
  let(:records) do
    {
      'locations' => [
        {
          'latitudeE7' => 525_320_000, 'longitudeE7' => 135_170_000, 'accuracy' => 30,
          'activity' => [{ 'activity' => [{ 'type' => 'STILL', 'confidence' => 90 }],
                           'timestamp' => '2024-06-22T19:41:35.000Z' }],
          'source' => 'WIFI', 'deviceTag' => -2_008_693_898,
          'timestamp' => '2024-06-22T19:41:31.000Z'
        },
        {
          'latitudeE7' => 544_392_000, 'longitudeE7' => 127_081_000, 'accuracy' => 12,
          'deviceTag' => -1_849_312_274,
          'timestamp' => '2024-06-22T20:08:58.000Z'
        },
        {
          'latitudeE7' => 544_376_000, 'longitudeE7' => 127_085_000, 'accuracy' => 12,
          'source' => 'GPS', 'deviceTag' => -1_849_312_274,
          'timestamp' => '2024-06-22T20:34:37.000Z'
        }
      ]
    }
  end

  def attach_records(payload)
    file = Tempfile.new(['records', '.json'])
    file.write(Oj.dump(payload, mode: :compat))
    file.rewind
    import.file.attach(io: file, filename: 'Records.json', content_type: 'application/json')
    file.close
  end

  def point_at(iso, tracker: 'google-maps-timeline-export', lonlat: 'POINT(13.517 52.532)')
    create(:point, user: user, import: import, tracker_id: tracker,
                   timestamp: Time.zone.parse(iso).to_i, lonlat: lonlat)
  end

  before { attach_records(records) }

  describe '#call' do
    it 'gives each device its own tracker_id' do
      home = point_at('2024-06-22T19:41:31Z')
      away_a = point_at('2024-06-22T20:08:58Z', lonlat: 'POINT(12.7081 54.4392)')
      away_b = point_at('2024-06-22T20:34:37Z', lonlat: 'POINT(12.7085 54.4376)')

      described_class.new(import).call

      expect(home.reload.tracker_id).to eq('google-records-device--2008693898')
      expect(away_a.reload.tracker_id).to eq('google-records-device--1849312274')
      expect(away_b.reload.tracker_id).to eq('google-records-device--1849312274')
    end

    it 'reports how many points it re-stamped' do
      point_at('2024-06-22T19:41:31Z')
      point_at('2024-06-22T20:08:58Z')

      expect(described_class.new(import).call).to eq(2)
    end

    it 'leaves points that already carry a device tracker alone' do
      already_done = point_at('2024-06-22T20:08:58Z', tracker: 'google-records-device--1849312274')

      expect { described_class.new(import).call }
        .not_to(change { already_done.reload.updated_at })
    end

    it 'leaves points from other imports alone' do
      other_import = create(:import, user: user, source: :google_records)
      stranger = create(:point, user: user, import: other_import,
                                tracker_id: 'google-maps-timeline-export',
                                timestamp: Time.zone.parse('2024-06-22T20:08:58Z').to_i)

      described_class.new(import).call

      expect(stranger.reload.tracker_id).to eq('google-maps-timeline-export')
    end

    it 'ignores nested activity timestamps when reading a record' do
      # 19:41:35 is the activity timestamp, not the location's own.
      decoy = point_at('2024-06-22T19:41:35Z')

      described_class.new(import).call

      expect(decoy.reload.tracker_id).to eq('google-maps-timeline-export')
    end

    # Two devices reporting in the same second is what leaves points stranded on
    # the shared tracker, and stranded points get stitched into 2-point tracks
    # hundreds of km long. The coordinates tell them apart.
    context 'when two devices report the same second' do
      let(:records) do
        {
          'locations' => [
            { 'latitudeE7' => 525_320_000, 'longitudeE7' => 135_170_000,
              'deviceTag' => 111, 'timestamp' => '2024-06-22T20:08:58.000Z' },
            { 'latitudeE7' => 544_392_000, 'longitudeE7' => 127_081_000,
              'deviceTag' => 222, 'timestamp' => '2024-06-22T20:08:58.100Z' }
          ]
        }
      end

      it 'tells the devices apart by position' do
        here = point_at('2024-06-22T20:08:58Z', lonlat: 'POINT(13.517 52.532)')
        there = point_at('2024-06-22T20:08:58Z', lonlat: 'POINT(12.7081 54.4392)')

        described_class.new(import).call

        expect(here.reload.tracker_id).to eq('google-records-device-111')
        expect(there.reload.tracker_id).to eq('google-records-device-222')
      end

      it 'leaves a point whose position matches neither record alone' do
        stranger = point_at('2024-06-22T20:08:58Z', lonlat: 'POINT(2.3522 48.8566)')

        described_class.new(import).call

        expect(stranger.reload.tracker_id).to eq('google-maps-timeline-export')
      end
    end

    context 'when the import file is gone' do
      it 'returns 0 without raising' do
        import.file.purge

        expect { expect(described_class.new(import).call).to eq(0) }.not_to raise_error
      end
    end

    context 'when the import is not a Google Records import' do
      let(:import) { create(:import, user: user, source: :gpx, name: 'track.gpx') }

      it 'returns 0 and changes nothing' do
        point = point_at('2024-06-22T20:08:58Z')

        expect(described_class.new(import).call).to eq(0)
        expect(point.reload.tracker_id).to eq('google-maps-timeline-export')
      end
    end
  end
end
