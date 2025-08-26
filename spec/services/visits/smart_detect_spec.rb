# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::SmartDetect do
  let(:user) { create(:user) }
  let(:start_at) { 1.day.ago }
  let(:end_at) { Time.current }
  let(:points) { create_list(:point, 5, user: user, timestamp: 2.hours.ago) }

  subject { described_class.new(user, start_at: start_at, end_at: end_at) }

  describe '#call' do
    context 'when there are no points' do
      it 'returns an empty array' do
        expect(subject.call).to eq([])
      end
    end

    context 'when there are points' do
      let(:visit_detector) { instance_double(Visits::Detector) }
      let(:visit_merger) { instance_double(Visits::Merger) }
      let(:visit_creator) { instance_double(Visits::Creator) }
      let(:potential_visits) { [{ id: 1 }] }
      let(:merged_visits) { [{ id: 2 }] }
      let(:grouped_visits) { [[{ id: 3 }]] }
      let(:created_visits) { [instance_double(Visit)] }

      before do
        allow(user).to receive_message_chain(:points, :not_visited, :order, :where).and_return(points)
        allow(Visits::Detector).to receive(:new).with(points).and_return(visit_detector)
        allow(Visits::Merger).to receive(:new).with(points).and_return(visit_merger)
        allow(Visits::Creator).to receive(:new).with(user).and_return(visit_creator)
        allow(visit_detector).to receive(:detect_potential_visits).and_return(potential_visits)
        allow(visit_merger).to receive(:merge_visits).with(potential_visits).and_return(merged_visits)
        allow(subject).to receive(:group_nearby_visits).with(merged_visits).and_return(grouped_visits)
        allow(visit_creator).to receive(:create_visits).with([{ id: 3 }]).and_return(created_visits)
      end

      it 'delegates to the appropriate services' do
        expect(subject.call).to eq(created_visits)
      end
    end
  end
end
