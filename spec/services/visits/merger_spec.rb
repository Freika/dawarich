# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Merger do
  let(:user) { create(:user) }
  let(:points) { double('Points') }

  subject { described_class.new(points) }

  describe '#merge_visits' do
    let(:visit1) do
      {
        start_time: 2.hours.ago.to_i,
        end_time: 1.hour.ago.to_i,
        center_lat: 40.7128,
        center_lon: -74.0060,
        points: [double('Point1'), double('Point2')]
      }
    end

    let(:visit2) do
      {
        start_time: 50.minutes.ago.to_i,
        end_time: 40.minutes.ago.to_i,
        center_lat: 40.7129,
        center_lon: -74.0061,
        points: [double('Point3'), double('Point4')]
      }
    end

    let(:visit3) do
      {
        start_time: 30.minutes.ago.to_i,
        end_time: 20.minutes.ago.to_i,
        center_lat: 40.7500,
        center_lon: -74.0500,
        points: [double('Point5'), double('Point6')]
      }
    end

    context 'when visits can be merged' do
      let(:visits) { [visit1, visit2, visit3] }
      before do
        allow(subject).to receive(:can_merge_visits?).with(visit1, visit2).and_return(true)
        allow(subject).to receive(:can_merge_visits?).with(anything, visit3).and_return(false)
      end

      it 'merges consecutive visits that meet criteria' do
        merged = subject.merge_visits(visits)

        expect(merged.size).to eq(2)
        expect(merged.first[:points].size).to eq(4)
        expect(merged.first[:end_time]).to eq(visit2[:end_time])
        expect(merged.last).to eq(visit3)
      end
    end

    context 'when visits cannot be merged' do
      let(:visits) { [visit1, visit2, visit3] }

      before do
        allow(subject).to receive(:can_merge_visits?).and_return(false)
      end

      it 'keeps visits separate' do
        merged = subject.merge_visits(visits)

        expect(merged.size).to eq(3)
        expect(merged).to eq(visits)
      end
    end

    context 'with empty visits array' do
      it 'returns an empty array' do
        expect(subject.merge_visits([])).to eq([])
      end
    end
  end
end
