# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Prepare do
  describe '#call' do
    let(:points) do
      [
        build(:point, latitude: 0, longitude: 0, timestamp: 1.day.ago),
        build(:point, latitude: 0.00001, longitude: 0.00001, timestamp: 1.day.ago + 5.minutes),
        build(:point, latitude: 0.00002, longitude: 0.00002, timestamp: 1.day.ago + 10.minutes),
        build(:point, latitude: 0.00003, longitude: 0.00003, timestamp: 1.day.ago + 15.minutes),
        build(:point, latitude: 0.00004, longitude: 0.00004, timestamp: 1.day.ago + 20.minutes),
        build(:point, latitude: 0.00005, longitude: 0.00005, timestamp: 1.day.ago + 25.minutes),
        build(:point, latitude: 0.00006, longitude: 0.00006, timestamp: 1.day.ago + 30.minutes),
        build(:point, latitude: 0.00007, longitude: 0.00007, timestamp: 1.day.ago + 35.minutes),
        build(:point, latitude: 0.00008, longitude: 0.00008, timestamp: 1.day.ago + 40.minutes),
        build(:point, latitude: 0.00009, longitude: 0.00009, timestamp: 1.day.ago + 45.minutes),
        build(:point, latitude: 0.0001,  longitude: 0.0001,  timestamp: 1.day.ago + 50.minutes),
        build(:point, latitude: 0.00011, longitude: 0.00011, timestamp: 1.day.ago + 55.minutes),
        build(:point, latitude: 0.00011, longitude: 0.00011, timestamp: 1.day.ago + 95.minutes),
        build(:point, latitude: 0.00011, longitude: 0.00011, timestamp: 1.day.ago + 100.minutes),
        build(:point, latitude: 0.00011, longitude: 0.00011, timestamp: 1.day.ago + 105.minutes)
      ]
    end

    subject { described_class.new(points).call }

    it 'returns correct visits' do
      expect(subject).to eq [
        {
          date: 1.day.ago.to_date.to_s,
          visits: [
            {
              latitude: 0.0,
              longitude: 0.0,
              radius: 10,
              points:,
              duration: 105,
              started_at: 1.day.ago.to_s,
              ended_at: (1.day.ago + 105.minutes).to_s
            }
          ]
        }
      ]
    end
  end
end
