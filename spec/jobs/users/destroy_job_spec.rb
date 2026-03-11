# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::DestroyJob, type: :job do
  let(:user) { create(:user) }
  let(:destroy_service) { instance_double(Users::Destroy, call: true) }

  before do
    allow(Users::Destroy).to receive(:new).and_return(destroy_service)
  end

  describe '#perform' do
    context 'when user exists and is soft-deleted' do
      before do
        user.mark_as_deleted!
      end

      it 'calls Users::Destroy service' do
        expect(Users::Destroy).to receive(:new).with(user).and_return(destroy_service)
        expect(destroy_service).to receive(:call)

        described_class.perform_now(user.id)
      end

      it 'logs the deletion process' do
        allow(Rails.logger).to receive(:info)

        described_class.perform_now(user.id)

        expect(Rails.logger).to have_received(:info).with("Starting hard deletion for user #{user.id} (#{user.email})")
        expect(Rails.logger).to have_received(:info).with("Successfully deleted user #{user.id}")
      end
    end

    context 'when user is not soft-deleted' do
      it 'does not call Users::Destroy service' do
        expect(Users::Destroy).not_to receive(:new)

        described_class.perform_now(user.id)
      end

      it 'logs that user was not found among soft-deleted users' do
        allow(Rails.logger).to receive(:info)

        described_class.perform_now(user.id)

        expect(Rails.logger).to have_received(:info).with(
          /User #{user.id} not found among soft-deleted users, skipping/
        )
      end
    end

    context 'when user does not exist' do
      it 'does not call Users::Destroy service' do
        expect(Users::Destroy).not_to receive(:new)

        described_class.perform_now(999_999)
      end

      it 'logs that user was not found' do
        allow(Rails.logger).to receive(:info)

        described_class.perform_now(999_999)

        expect(Rails.logger).to have_received(:info).with(
          /User 999999 not found among soft-deleted users, skipping/
        )
      end
    end

    context 'when user has already been hard deleted' do
      it 'logs and skips without raising' do
        user.mark_as_deleted!
        user.delete # Hard delete

        allow(Rails.logger).to receive(:info)

        described_class.perform_now(user.id)

        expect(Rails.logger).to have_received(:info).with(
          /User #{user.id} not found among soft-deleted users, skipping/
        )
      end
    end

    context 'when deletion fails with StandardError' do
      before do
        user.mark_as_deleted!
        allow(destroy_service).to receive(:call).and_raise(StandardError, 'Database error')
      end

      it 'reports the exception and re-raises for Sidekiq retry' do
        allow(ExceptionReporter).to receive(:call)

        expect { described_class.perform_now(user.id) }.to raise_error(StandardError, 'Database error')

        expect(ExceptionReporter).to have_received(:call).with(
          instance_of(StandardError),
          "User deletion failed for user_id #{user.id}"
        )
      end
    end

    context 'when deletion fails with RecordInvalid' do
      before do
        user.mark_as_deleted!
        allow(destroy_service).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(user))
      end

      it 'reports but does not re-raise (not transient)' do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)
        allow(ExceptionReporter).to receive(:call)

        expect { described_class.perform_now(user.id) }.not_to raise_error
      end
    end

    context 'with retry configuration' do
      it 'retries up to 3 times on failure' do
        expect(described_class.get_sidekiq_options['retry']).to eq(3)
      end
    end

    context 'when user owns a family with members' do
      let(:family) { create(:family, creator: user) }
      let(:other_member) { create(:user) }

      before do
        user.mark_as_deleted!
        create(:family_membership, user: user, family: family, role: :owner)
        create(:family_membership, user: other_member, family: family, role: :member)

        allow(Users::Destroy).to receive(:new).and_call_original
      end

      it 'handles validation error gracefully' do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)
        allow(ExceptionReporter).to receive(:call)

        described_class.perform_now(user.id)

        expect(Rails.logger).to have_received(:error).with(
          /User deletion blocked for user_id #{user.id}/
        )
        expect(ExceptionReporter).to have_received(:call).with(
          instance_of(ActiveRecord::RecordInvalid),
          "User deletion blocked for user_id #{user.id}"
        )
      end

      it 'does not delete the user' do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)
        allow(ExceptionReporter).to receive(:call)

        described_class.perform_now(user.id)

        expect(User.deleted.find_by(id: user.id)).to be_present
      end

      it 'does not log success message' do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)
        allow(ExceptionReporter).to receive(:call)

        described_class.perform_now(user.id)

        expect(Rails.logger).not_to have_received(:info).with("Successfully deleted user #{user.id}")
      end
    end
  end
end
