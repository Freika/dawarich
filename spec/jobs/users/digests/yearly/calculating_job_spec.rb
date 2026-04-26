# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::Yearly::CalculatingJob, type: :job do
  describe '#perform' do
    let!(:user) { create(:user) }
    let(:year) { 2024 }

    it 'enqueues to the digests queue' do
      expect(described_class.new.queue_name).to eq('digests')
    end

    context 'when the user has stats for the year' do
      let!(:january_stat) do
        create(:stat, user: user, year: year, month: 1, distance: 100,
                      toponyms: [{ 'country' => 'Spain',
                                   'cities' => [{ 'city' => 'Madrid', 'stayed_for' => 60 }] }])
      end
      let!(:february_stat) do
        create(:stat, user: user, year: year, month: 2, distance: 200,
                      toponyms: [{ 'country' => 'Spain',
                                   'cities' => [{ 'city' => 'Madrid', 'stayed_for' => 60 }] }])
      end

      it 'persists a yearly Users::Digest record for the year' do
        expect do
          described_class.new.perform(user.id, year)
        end.to change { Users::Digest.where(user: user, year: year, period_type: :yearly).count }.by(1)
      end

      it 'records the structural fields on the digest' do
        described_class.new.perform(user.id, year)

        digest = user.digests.yearly.find_by(year: year)
        expect(digest).to be_present
        expect(digest.period_type).to eq('yearly')
        expect(digest.year).to eq(year)
      end

      it 'chains Yearly::EmailSendingJob on success' do
        expect do
          described_class.new.perform(user.id, year)
        end.to have_enqueued_job(Users::Digests::Yearly::EmailSendingJob).with(user.id, year)
      end
    end

    context 'when an error is raised during calculation' do
      before do
        allow(Users::Digests::CalculateYear).to receive(:new).and_raise(StandardError.new('boom'))
      end

      it 'creates an error notification with the Year-End title' do
        expect do
          described_class.new.perform(user.id, year)
        end.to change { user.reload.notifications.where(kind: :error).count }.by(1)

        last = user.notifications.where(kind: :error).order(:id).last
        expect(last.title).to include('Year-End Digest')
      end

      it 'does not enqueue the email job on failure' do
        expect do
          described_class.new.perform(user.id, year)
        end.not_to have_enqueued_job(Users::Digests::Yearly::EmailSendingJob)
      end
    end

    context 'when the user does not exist' do
      it 'does not raise an error' do
        expect do
          described_class.new.perform(999_999, year)
        end.not_to raise_error
      end
    end
  end
end
