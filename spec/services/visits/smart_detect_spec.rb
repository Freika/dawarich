# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::SmartDetect do
  let(:user) { create(:user) }
  let(:start_at) { 1.day.ago }
  let(:end_at) { Time.current }

  subject { described_class.new(user, start_at: start_at, end_at: end_at) }

  describe '#call' do
    context 'when there are no points' do
      it 'returns an empty array' do
        expect(subject.call).to eq([])
      end
    end

    context 'when there are points' do
      let!(:points) do
        create_list(:point, 5, user: user, timestamp: 2.hours.ago, visit_id: nil, anomaly: false)
      end
      let(:potential_visits) { [{ id: 1, center_lat: 40.7128, center_lon: -74.0060 }] }
      let(:merged_visits) { [{ id: 2, center_lat: 40.7128, center_lon: -74.0060 }] }
      let(:created_visits) { [instance_double(Visit)] }

      before do
        allow(Visits::Detector).to receive(:new).and_return(instance_double(Visits::Detector, detect_potential_visits: potential_visits))
        allow(Visits::Merger).to receive(:new).and_return(instance_double(Visits::Merger, merge_visits: merged_visits))
        allow(Visits::Creator).to receive(:new).with(user).and_return(instance_double(Visits::Creator, create_visits: created_visits))
      end

      it 'delegates to the appropriate services and returns created visits' do
        expect(subject.call).to eq(created_visits)
      end
    end
  end
end
