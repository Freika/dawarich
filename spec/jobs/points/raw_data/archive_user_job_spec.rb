# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::ArchiveUserJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }
    let(:archiver) { instance_double(Points::RawData::Archiver) }

    before do
      allow(Points::RawData::Archiver).to receive(:new).and_return(archiver)
      allow(archiver).to receive(:archive_user).and_return({ processed: 1, archived: 100, failed: 0 })
    end

    it 'calls the archiver service for the user' do
      expect(archiver).to receive(:archive_user).with(user.id)

      described_class.perform_now(user.id)
    end

    it 'is enqueued in the archival queue' do
      expect { described_class.perform_later(user.id) }
        .to have_enqueued_job.on_queue('archival')
    end

    context 'when user does not exist' do
      it 'skips without error' do
        expect(archiver).not_to receive(:archive_user)

        expect { described_class.perform_now(-1) }.not_to raise_error
      end
    end

    context 'when advisory lock is held' do
      it 'skips without error' do
        # Simulate lock being held by not allowing the block to execute
        allow(ActiveRecord::Base).to receive(:with_advisory_lock).and_return(false)

        expect(archiver).not_to receive(:archive_user)

        described_class.perform_now(user.id)
      end
    end

    context 'when archiver raises an error' do
      before do
        allow(archiver).to receive(:archive_user).and_raise(StandardError, 'Archive failed')
      end

      it 'reports and re-raises the error' do
        expect(ExceptionReporter).to receive(:call)
        expect { described_class.perform_now(user.id) }.to raise_error(StandardError, 'Archive failed')
      end
    end
  end
end
