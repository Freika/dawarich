# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkVisitsSuggestingJob, type: :job do
  describe 'backward-compatible singular user_id keyword' do
    let!(:target_user) { create(:user) }
    let!(:other_user)  { create(:user) }
    let(:start_at) { 1.day.ago.beginning_of_day }
    let(:end_at)   { 1.day.ago.end_of_day }

    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
      allow_any_instance_of(Visits::TimeChunks).to receive(:call).and_return([[start_at, end_at]])
      create(:point, user: target_user)
      create(:point, user: other_user)
    end

    it 'does not raise ArgumentError when invoked with the singular user_id keyword' do
      expect do
        described_class.perform_now(user_id: target_user.id)
      end.not_to raise_error
    end

    it 'enqueues VisitSuggestingJob only for the user named by the singular user_id keyword' do
      described_class.perform_now(user_id: target_user.id)

      expect(VisitSuggestingJob).to have_been_enqueued.with(
        user_id: target_user.id, start_at: start_at, end_at: end_at
      )
      expect(VisitSuggestingJob).not_to have_been_enqueued.with(
        user_id: other_user.id, start_at: anything, end_at: anything
      )
    end

    it 'tolerates the singular user_id keyword combined with start_at and end_at' do
      custom_start = 3.days.ago.beginning_of_day
      custom_end   = 3.days.ago.end_of_day
      allow_any_instance_of(Visits::TimeChunks).to receive(:call).and_return([[custom_start, custom_end]])

      expect do
        described_class.perform_now(user_id: target_user.id, start_at: custom_start, end_at: custom_end)
      end.not_to raise_error

      expect(VisitSuggestingJob).to have_been_enqueued.with(
        user_id: target_user.id, start_at: custom_start, end_at: custom_end
      )
    end
  end
end
