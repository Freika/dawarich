# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::Monthly::CalculatingJob, type: :job do
  let(:user) { create(:user) }
  let(:year)  { 2026 }
  let(:month) { 3 }

  context 'when the user has points and stats for the period' do
    before do
      day_1 = Time.zone.local(year, month, 1, 10, 0, 0).to_i
      day_2 = Time.zone.local(year, month, 2, 10, 0, 0).to_i
      create(:point, user: user, timestamp: day_1, country_name: 'Spain', city: 'Madrid')
      create(:point, user: user, timestamp: day_2, country_name: 'Spain', city: 'Madrid')

      create(:stat, user: user, year: year, month: month, distance: 12_345,
                    toponyms: [{ 'country' => 'Spain',
                                 'cities' => [{ 'city' => 'Madrid', 'stayed_for' => 600 }] }])
    end

    it 'persists a monthly Users::Digest record for the period' do
      expect do
        described_class.new.perform(user.id, year, month)
      end.to change { Users::Digest.where(user: user, year: year, month: month, period_type: :monthly).count }.by(1)
    end

    it 'records the digest with the correct period and year/month' do
      described_class.new.perform(user.id, year, month)

      digest = user.digests.monthly.find_by(year: year, month: month)

      expect(digest).to be_present
      expect(digest.period_type).to eq('monthly')
      expect(digest.year).to eq(year)
      expect(digest.month).to eq(month)
    end

    it 'chains Monthly::EmailSendingJob on success' do
      expect do
        described_class.new.perform(user.id, year, month)
      end.to have_enqueued_job(Users::Digests::Monthly::EmailSendingJob).with(user.id, year, month)
    end
  end

  context 'when an error is raised during calculation' do
    before do
      allow(Stats::CalculateMonth).to receive(:new).and_raise(StandardError.new('boom'))
    end

    it 'creates an error notification for the user' do
      expect do
        described_class.new.perform(user.id, year, month)
      end.to change { user.reload.notifications.where(kind: :error).count }.by(1)
    end

    it 'does not enqueue the email job' do
      expect do
        described_class.new.perform(user.id, year, month)
      end.not_to have_enqueued_job(Users::Digests::Monthly::EmailSendingJob)
    end
  end
end
