# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VisitSuggestingJob, type: :job do
  let(:user) { create(:user) }
  let(:start_at) { DateTime.now.beginning_of_day - 1.day }
  let(:end_at) { DateTime.now.end_of_day }

  describe '#perform' do
    subject { described_class.perform_now(user_id: user.id, start_at: start_at, end_at: end_at) }

    context 'when time range is valid' do
      before do
        allow(Visits::Suggest).to receive(:new).and_call_original
        allow_any_instance_of(Visits::Suggest).to receive(:call)
      end

      it 'processes each day in the time range' do
        # With a 2-day range, we should call Suggest twice (once per day)
        expect(Visits::Suggest).to receive(:new).twice.and_call_original
        subject
      end

      it 'passes the correct parameters to the Suggest service' do
        # First day
        first_day_start = start_at.to_datetime
        first_day_end = (first_day_start + 1.day)

        expect(Visits::Suggest).to receive(:new)
          .with(user,
                start_at: first_day_start,
                end_at: first_day_end)
          .and_call_original

        # Second day
        second_day_start = first_day_end
        second_day_end = end_at.to_datetime

        expect(Visits::Suggest).to receive(:new)
          .with(user,
                start_at: second_day_start,
                end_at: second_day_end)
          .and_call_original

        subject
      end
    end

    context 'when time range spans multiple days' do
      let(:start_at) { DateTime.now.beginning_of_day - 3.days }
      let(:end_at) { DateTime.now.end_of_day }

      before do
        allow(Visits::Suggest).to receive(:new).and_call_original
        allow_any_instance_of(Visits::Suggest).to receive(:call)
      end

      it 'processes each day in the range' do
        # With a 4-day range, we should call Suggest 4 times
        expect(Visits::Suggest).to receive(:new).exactly(4).times.and_call_original
        subject
      end
    end

    context 'with string dates' do
      let(:string_start) { start_at.to_s }
      let(:string_end) { end_at.to_s }
      let(:parsed_start) { start_at.to_datetime }
      let(:parsed_end) { end_at.to_datetime }

      before do
        allow(Visits::Suggest).to receive(:new).and_call_original
        allow_any_instance_of(Visits::Suggest).to receive(:call)
        allow(Time.zone).to receive(:parse).with(string_start).and_return(parsed_start)
        allow(Time.zone).to receive(:parse).with(string_end).and_return(parsed_end)
      end

      it 'handles string date parameters correctly' do
        # At minimum we expect one call to Suggest
        expect(Visits::Suggest).to receive(:new).at_least(:once).and_call_original

        described_class.perform_now(
          user_id: user.id,
          start_at: string_start,
          end_at: string_end
        )
      end
    end

    context 'when user is inactive' do
      before do
        user.update(status: :inactive, active_until: 1.day.ago)

        allow(Visits::Suggest).to receive(:new).and_call_original
        allow_any_instance_of(Visits::Suggest).to receive(:call)
      end

      it 'still processes the job for the specified user' do
        # The job doesn't check for user active status, it just processes whatever user is passed
        expect(Visits::Suggest).to receive(:new).at_least(:once).and_call_original

        subject
      end
    end
  end

  describe 'queue name' do
    it 'uses the visit_suggesting queue' do
      expect(described_class.queue_name).to eq('visit_suggesting')
    end
  end
end
