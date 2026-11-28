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

      expect { described_class.perform_now }.to have_enqueued_job(Points::RawData::ArchiveUserJob).at_least(3).times

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

    context 'when ARCHIVE_ENCRYPTION_KEY is missing in production' do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('ARCHIVE_ENCRYPTION_KEY', nil).and_return(nil)
        allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
      end

      it 'reports the missing key and enqueues nothing' do
        create(:user)
        allow(ExceptionReporter).to receive(:call)

        expect { described_class.perform_now }.not_to have_enqueued_job(Points::RawData::ArchiveUserJob)
        expect(ExceptionReporter).to have_received(:call)
          .with(instance_of(Points::RawData::Encryption::KeyNotConfigured), anything)
      end
    end

    context 'when an error occurs' do
      before do
        allow(User).to receive(:ids).and_raise(StandardError, 'DB error')
      end

      it 'reports and re-raises the error' do
        expect(ExceptionReporter).to receive(:call)
        expect { described_class.perform_now }.to raise_error(StandardError, 'DB error')
      end
    end
  end
end
