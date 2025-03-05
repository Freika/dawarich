# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::MergeService do
  let(:user) { create(:user) }
  let(:place) { create(:place) }

  let(:visit1) do
    create(:visit,
           user: user,
           place: place,
           started_at: 2.days.ago,
           ended_at: 1.day.ago,
           duration: 1440,
           name: 'Visit 1',
           status: 'suggested')
  end

  let(:visit2) do
    create(:visit,
           user: user,
           place: place,
           started_at: 1.day.ago,
           ended_at: Time.current,
           duration: 1440,
           name: 'Visit 2',
           status: 'suggested')
  end

  let!(:point1) { create(:point, user: user, visit: visit1) }
  let!(:point2) { create(:point, user: user, visit: visit2) }

  describe '#call' do
    context 'with valid visits' do
      it 'merges visits successfully' do
        service = described_class.new([visit1, visit2])
        result = service.call

        expect(result).to be_persisted
        expect(result.id).to eq(visit1.id)
        expect(result.started_at).to eq(visit1.started_at)
        expect(result.ended_at).to eq(visit2.ended_at)
        expect(result.status).to eq('confirmed')
        expect(result.points.count).to eq(2)
      end

      it 'deletes the second visit' do
        service = described_class.new([visit1, visit2])
        service.call

        expect { visit2.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'creates a combined name for the merged visit' do
        service = described_class.new([visit1, visit2])
        result = service.call

        expected_name = "Combined Visit (#{visit1.started_at.strftime('%b %d')} - #{visit2.ended_at.strftime('%b %d')})"
        expect(result.name).to eq(expected_name)
      end

      it 'calculates the correct duration' do
        service = described_class.new([visit1, visit2])
        result = service.call

        # Total duration should be from earliest start to latest end
        expected_duration = ((visit2.ended_at - visit1.started_at) / 60).round
        expect(result.duration).to eq(expected_duration)
      end
    end

    context 'with less than 2 visits' do
      it 'returns nil and adds an error' do
        service = described_class.new([visit1])
        result = service.call

        expect(result).to be_nil
        expect(service.errors).to include('At least 2 visits must be selected for merging')
      end
    end

    context 'when a database error occurs' do
      before do
        allow(visit1).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(visit1))
        allow(visit1).to receive_message_chain(:errors, :full_messages, :join).and_return('Error message')
      end

      it 'handles ActiveRecord errors' do
        service = described_class.new([visit1, visit2])
        result = service.call

        expect(result).to be_nil
        expect(service.errors).to include('Error message')
      end
    end
  end
end
