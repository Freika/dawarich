# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::Digests transitional aliases', type: :job do
  describe 'Users::Digests::EmailSendingJob' do
    it 'resolves to a real class via constantize' do
      expect { 'Users::Digests::EmailSendingJob'.constantize }.not_to raise_error
    end

    it 'is a subclass of the renamed Users::Digests::Yearly::EmailSendingJob' do
      expect('Users::Digests::EmailSendingJob'.constantize)
        .to be < Users::Digests::Yearly::EmailSendingJob
    end

    it 'enqueues to the same mailers queue as the renamed yearly job' do
      expect(Users::Digests::EmailSendingJob.new.queue_name)
        .to eq(Users::Digests::Yearly::EmailSendingJob.new.queue_name)
    end

    it 'can be enqueued via perform_later (unblocks legacy schedule entries)' do
      user = create(:user)
      expect do
        Users::Digests::EmailSendingJob.perform_later(user.id, 2025)
      end.to have_enqueued_job(Users::Digests::EmailSendingJob).with(user.id, 2025)
    end
  end

  describe 'Users::Digests::CalculatingJob' do
    it 'resolves to a real class via constantize' do
      expect { 'Users::Digests::CalculatingJob'.constantize }.not_to raise_error
    end

    it 'is a subclass of the renamed Users::Digests::Yearly::CalculatingJob' do
      expect('Users::Digests::CalculatingJob'.constantize)
        .to be < Users::Digests::Yearly::CalculatingJob
    end

    it 'enqueues to the same digests queue as the renamed yearly job' do
      expect(Users::Digests::CalculatingJob.new.queue_name)
        .to eq(Users::Digests::Yearly::CalculatingJob.new.queue_name)
    end
  end
end
