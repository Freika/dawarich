# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::ArchiveJob, type: :job do
  describe '#perform' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
    end

    it 'enqueues an ArchiveUserJob for each user' do
      users = create_list(:user, 3)

      expect { described_class.perform_now }.to have_enqueued_job(Points::RawData::ArchiveUserJob).exactly(3).times

      users.each do |user|
        expect(Points::RawData::ArchiveUserJob).to have_been_enqueued.with(user.id)
      end
    end

    context 'when ARCHIVE_RAW_DATA is not true' do
      before do
        allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('false')
      end

      it 'does not enqueue any jobs' do
        create(:user)

        expect { described_class.perform_now }.not_to have_enqueued_job(Points::RawData::ArchiveUserJob)
      end
    end

    context 'when an error occurs' do
      before do
        allow(User).to receive(:find_each).and_raise(StandardError, 'DB error')
      end

      it 'reports and re-raises the error' do
        expect(ExceptionReporter).to receive(:call)
        expect { described_class.perform_now }.to raise_error(StandardError, 'DB error')
      end
    end
  end
end
