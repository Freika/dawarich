# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationJob do
  describe '#find_user_or_skip' do
    # Create a concrete job class to test the helper
    let(:job_class) do
      Class.new(ApplicationJob) do
        self.queue_adapter = :test

        def perform(user_id)
          find_user_or_skip(user_id)
        end

        # Expose class name for log messages
        def self.name
          'TestJob'
        end
      end
    end

    context 'when user exists' do
      let(:user) { create(:user) }

      it 'returns the user' do
        result = job_class.new.perform(user.id)
        expect(result).to eq(user)
      end
    end

    context 'when user does not exist' do
      it 'returns nil' do
        result = job_class.new.perform(999_999)
        expect(result).to be_nil
      end

      it 'logs that the user was not found' do
        allow(Rails.logger).to receive(:info)

        job_class.new.perform(999_999)

        expect(Rails.logger).to have_received(:info).with(
          'TestJob: User 999999 not found, skipping'
        )
      end
    end

    context 'when user is soft-deleted' do
      let(:user) { create(:user) }

      before { user.mark_as_deleted! }

      it 'returns nil' do
        result = job_class.new.perform(user.id)
        expect(result).to be_nil
      end

      it 'logs that the user was not found' do
        allow(Rails.logger).to receive(:info)

        job_class.new.perform(user.id)

        expect(Rails.logger).to have_received(:info).with(
          "TestJob: User #{user.id} not found, skipping"
        )
      end
    end
  end
end
