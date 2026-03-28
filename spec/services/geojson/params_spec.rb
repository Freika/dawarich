# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geojson::Params do
  describe 'field alias detection' do
    let(:fixture_path) { Rails.root.join('spec/fixtures/files/geojson/various_fields.geojson') }
    let(:json) { JSON.parse(File.read(fixture_path)) }
    let(:result) { described_class.new(json).call }

    it 'extracts points from all features' do
      expect(result.size).to eq(3)
    end

    it 'parses datetime alias for timestamp' do
      expect(result[0][:timestamp]).not_to be_nil
    end

    it 'parses when alias for timestamp' do
      expect(result[1][:timestamp]).not_to be_nil
    end

    it 'parses recorded_at alias for timestamp' do
      expect(result[2][:timestamp]).not_to be_nil
    end

    it 'parses vel alias for velocity' do
      expect(result[0][:velocity]).to eq(1.5)
    end

    it 'converts speed_kmh to m/s' do
      expect(result[1][:velocity]).to eq(1.5) # 5.4 / 3.6 = 1.5
    end

    it 'parses acc alias for accuracy' do
      expect(result[0][:accuracy]).to eq(8)
    end

    it 'parses hdop alias for accuracy' do
      expect(result[1][:accuracy]).to eq(12)
    end

    it 'parses precision alias for accuracy' do
      expect(result[2][:accuracy]).to eq(5)
    end

    it 'parses batt alias for battery' do
      expect(result[0][:battery]).to eq(72)
    end

    it 'parses height alias for altitude' do
      expect(result[2][:altitude]).to eq(36.0)
    end
  end

  describe '#call' do
    subject { described_class.new(json).call }

    context 'when the json is an Overland export' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/export.json') }
      let(:json) { JSON.parse(File.read(file_path)) }

      it 'returns an array of points' do
        expect(subject).to be_an_instance_of(Array)
        expect(subject.first).to be_an_instance_of(Hash)
      end

      it 'returns the correct number of points' do
        expect(subject.size).to eq(10)
      end

      it 'extracts coordinates' do
        expect(subject.first[:lonlat]).to eq('POINT(0.1 0.1)')
      end

      it 'extracts timestamp' do
        expect(subject.first[:timestamp]).to eq(1_609_459_201)
      end

      it 'extracts altitude' do
        expect(subject.first[:altitude]).to eq(1)
      end

      it 'extracts velocity' do
        expect(subject.first[:velocity]).to eq(1.5)
      end

      it 'extracts accuracy' do
        expect(subject.first[:accuracy]).to eq(1)
      end

      it 'extracts vertical accuracy' do
        expect(subject.first[:vertical_accuracy]).to eq(1)
      end

      it 'extracts tracker_id' do
        expect(subject.first[:tracker_id]).to eq('MyString')
      end

      it 'stores raw_data as the original feature' do
        expect(subject.first[:raw_data]).to be_a(Hash)
        expect(subject.first[:raw_data]['type']).to eq('Feature')
      end
    end

    context 'when the json is exported from GPSLogger' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/gpslogger_example.json') }
      let(:json) { JSON.parse(File.read(file_path)) }

      it 'extracts coordinates' do
        expect(subject.first[:lonlat]).to eq('POINT(106.64234449272531 10.758321212464024)')
      end

      it 'extracts timestamp from time field' do
        expect(subject.first[:timestamp]).to eq(Time.zone.parse('2024-11-03T16:30:11.331+07:00').utc.to_i)
      end

      it 'extracts altitude' do
        expect(subject.first[:altitude]).to eq(17.634344400269068)
      end

      it 'extracts speed as velocity' do
        expect(subject.first[:velocity]).to eq(1.2)
      end

      it 'extracts accuracy' do
        expect(subject.first[:accuracy]).to eq(4.7551565)
      end

      it 'stores raw_data as the original feature' do
        expect(subject.first[:raw_data]).to be_a(Hash)
        expect(subject.first[:raw_data]['type']).to eq('Feature')
      end
    end

    context 'when the json is exported from Google Takeout' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/google_takeout_example.json') }
      let(:json) { JSON.parse(File.read(file_path)) }

      it 'extracts coordinates' do
        expect(subject.first[:lonlat]).to eq('POINT(28 36)')
      end

      it 'extracts timestamp from date field' do
        expect(subject.first[:timestamp]).to eq(Time.zone.parse('2016-06-21T06:09:33Z').utc.to_i)
      end

      it 'returns zero velocity when no speed field present' do
        expect(subject.first[:velocity]).to eq(0.0)
      end

      it 'returns nil for missing fields' do
        first = subject.first
        expect(first[:altitude]).to be_nil
        expect(first[:accuracy]).to be_nil
        expect(first[:battery]).to be_nil
      end

      it 'stores raw_data as the original feature' do
        expect(subject.first[:raw_data]).to be_a(Hash)
        expect(subject.first[:raw_data]['type']).to eq('Feature')
      end
    end
  end
end
