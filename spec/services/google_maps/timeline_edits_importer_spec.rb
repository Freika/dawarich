# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::TimelineEditsImporter do
  describe '#call' do
    subject(:parser) { described_class.new(import).call(timeline_edits) }

    let(:import) { create(:import, source: 'google_timeline_edits') }

    let(:gps_entry) do
      {
        'deviceId' => '799010011',
        'rawSignal' => {
          'signal' => {
            'position' => {
              'point' => { 'latE7' => 679_646_505, 'lngE7' => 236_864_785 },
              'accuracyMm' => 9000,
              'altitudeMeters' => 280.0,
              'source' => 'GPS',
              'timestamp' => '2024-03-13T14:43:00.805Z',
              'speedMetersPerSecond' => 1.5
            }
          }
        }
      }
    end

    let(:wifi_entry) do
      {
        'deviceId' => '799010011',
        'rawSignal' => {
          'signal' => {
            'position' => {
              'point' => { 'latE7' => 679_651_561, 'lngE7' => 236_850_278 },
              'accuracyMm' => 98_000,
              'altitudeMeters' => 280.0,
              'source' => 'WIFI',
              'timestamp' => '2024-03-13T14:43:36.723Z'
            }
          }
        }
      }
    end

    let(:activity_record_entry) do
      {
        'deviceId' => '799010011',
        'rawSignal' => {
          'signal' => {
            'activityRecord' => {
              'detectedActivities' => [{ 'activityType' => 'STILL', 'probability' => 0.4 }],
              'timestamp' => '2024-03-13T14:43:35.683Z'
            }
          }
        }
      }
    end

    let(:wifi_scan_entry) do
      {
        'deviceId' => '799010011',
        'rawSignal' => {
          'signal' => {
            'wifiScan' => {
              'deliveryTime' => '2024-03-13T14:43:36.723Z',
              'devices' => [{ 'mac' => '92494487099310', 'rawRssi' => -88 }]
            }
          }
        }
      }
    end

    let(:place_aggregates_entry) do
      {
        'deviceId' => '0',
        'placeAggregates' => {
          'placeAggregateInfo' => [
            { 'point' => { 'latE7' => 667_874_067, 'lngE7' => 240_053_221 }, 'placeId' => 'ChIJ...' }
          ]
        }
      }
    end

    let(:semantic_segment_entry) do
      {
        'deviceId' => '0',
        'userEditedSemanticSegment' => {
          'startTime' => '2024-03-13T01:40:59Z',
          'endTime' => '2024-03-13T02:45:18Z',
          'segment' => { 'activity' => { 'topCandidate' => { 'type' => 'IN_PASSENGER_VEHICLE' } } }
        }
      }
    end

    let(:position_without_point_entry) do
      {
        'deviceId' => '799010011',
        'rawSignal' => {
          'signal' => {
            'position' => {
              'point' => nil,
              'accuracyMm' => 1000,
              'timestamp' => '2024-03-13T14:50:00.000Z'
            }
          }
        }
      }
    end

    context 'with a single GPS position entry' do
      let(:timeline_edits) { [gps_entry] }

      it 'creates a Point' do
        expect { parser }.to change(Point, :count).by(1)
      end

      it 'converts latE7/lngE7 to decimal degrees' do
        parser
        point = Point.last
        expect(point.lon.to_f).to be_within(1e-7).of(23.6864785)
        expect(point.lat.to_f).to be_within(1e-7).of(67.9646505)
      end

      it 'converts accuracyMm to meters' do
        parser
        expect(Point.last.accuracy).to eq(9.0)
      end

      it 'maps altitude, velocity, and timestamp' do
        parser
        point = Point.last
        expect(point.altitude).to eq(280)
        expect(point.velocity.to_f).to eq(1.5)
        expect(point.timestamp).to eq(DateTime.parse('2024-03-13T14:43:00.805Z').to_i)
      end

      it 'sets the topic and tracker_id' do
        parser
        point = Point.last
        expect(point.topic).to eq('Google Timeline Edits')
        expect(point.tracker_id).to eq('google-timeline-edits')
      end

      it 'stores the original entry as raw_data' do
        parser
        expect(Point.last.raw_data).to eq(gps_entry)
      end
    end

    context 'with mixed signal types' do
      let(:timeline_edits) do
        [gps_entry, wifi_entry, activity_record_entry, wifi_scan_entry,
         place_aggregates_entry, semantic_segment_entry, position_without_point_entry]
      end

      it 'imports only the position entries' do
        expect { parser }.to change(Point, :count).by(2)
      end
    end

    context 'when speedMetersPerSecond is missing' do
      let(:entry) do
        gps = gps_entry.dup
        gps['rawSignal']['signal']['position'] = gps_entry['rawSignal']['signal']['position'].except('speedMetersPerSecond')
        gps
      end
      let(:timeline_edits) { [entry] }

      it 'creates the Point with nil velocity' do
        expect { parser }.to change(Point, :count).by(1)
        expect(Point.last.velocity).to be_nil
      end
    end

    context 'when accuracyMm is missing' do
      let(:entry) do
        gps = Marshal.load(Marshal.dump(gps_entry))
        gps['rawSignal']['signal']['position'].delete('accuracyMm')
        gps
      end
      let(:timeline_edits) { [entry] }

      it 'creates the Point with nil accuracy' do
        expect { parser }.to change(Point, :count).by(1)
        expect(Point.last.accuracy).to be_nil
      end
    end

    context 'with a duplicate position (same lonlat + timestamp)' do
      let(:timeline_edits) { [gps_entry, gps_entry] }

      it 'inserts only one Point (deduped by upsert_all)' do
        expect { parser }.to change(Point, :count).by(1)
      end
    end
  end
end
