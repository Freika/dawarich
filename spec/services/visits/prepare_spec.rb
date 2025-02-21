# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Prepare do
  describe '#call' do
    let(:static_time) { Time.zone.local(2021, 1, 1, 0, 0, 0) }
    let(:points) do
      [
        build(:point, lonlat: 'POINT(0 0)', timestamp: static_time),
        build(:point, lonlat: 'POINT(0.00001 0.00001)', timestamp: static_time + 5.minutes),
        build(:point, lonlat: 'POINT(0.00002 0.00002)', timestamp: static_time + 10.minutes),
        build(:point, lonlat: 'POINT(0.00003 0.00003)', timestamp: static_time + 15.minutes),
        build(:point, lonlat: 'POINT(0.00004 0.00004)', timestamp: static_time + 20.minutes),
        build(:point, lonlat: 'POINT(0.00005 0.00005)', timestamp: static_time + 25.minutes),
        build(:point, lonlat: 'POINT(0.00006 0.00006)', timestamp: static_time + 30.minutes),
        build(:point, lonlat: 'POINT(0.00007 0.00007)', timestamp: static_time + 35.minutes),
        build(:point, lonlat: 'POINT(0.00008 0.00008)', timestamp: static_time + 40.minutes),
        build(:point, lonlat: 'POINT(0.00009 0.00009)', timestamp: static_time + 45.minutes),
        build(:point, lonlat: 'POINT(0.0001 0.0001)', timestamp: static_time + 50.minutes),
        build(:point, lonlat: 'POINT(0.00011 0.00011)', timestamp: static_time + 55.minutes),
        build(:point, lonlat: 'POINT(0.00011 0.00011)', timestamp: static_time + 95.minutes),
        build(:point, lonlat: 'POINT(0.00011 0.00011)', timestamp: static_time + 100.minutes),
        build(:point, lonlat: 'POINT(0.00011 0.00011)', timestamp: static_time + 105.minutes)
      ]
    end

    subject { described_class.new(points).call }

    it 'returns correct visits' do
      expect(subject).to eq [
        {
          date: static_time.to_date.to_s,
          visits: [
            {
              latitude: '0.0',
              longitude: '0.0',
              radius: 10,
              points:,
              duration: 105,
              started_at: static_time.to_s,
              ended_at: (static_time + 105.minutes).to_s
            }
          ]
        }
      ]
    end
  end
end
