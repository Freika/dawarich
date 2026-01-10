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

      it 'returns early without processing' do
        expect(destroy_service).not_to receive(:call)

        described_class.perform_now(user.id)
      end
    end

    context 'when user does not exist' do
      it 'does not call Users::Destroy service' do
        expect(Users::Destroy).not_to receive(:new)

        described_class.perform_now(999_999)
      end
    end

    context 'when user has already been hard deleted' do
      it 'logs a warning' do
        user.mark_as_deleted!
        user.delete  # Hard delete

        allow(Rails.logger).to receive(:warn)

        described_class.perform_now(user.id)

        # Should not raise error, just skip
        expect(Rails.logger).not_to have_received(:warn)
      end
    end

    context 'when deletion fails' do
      before do
        user.mark_as_deleted!
        allow(destroy_service).to receive(:call).and_raise(StandardError, 'Database error')
      end

      it 'reports the exception' do
        expect(ExceptionReporter).to receive(:call).with(
          instance_of(StandardError),
          "User deletion failed for user_id #{user.id}"
        )

        described_class.perform_now(user.id)
      end

      it 'does not log success message' do
        allow(Rails.logger).to receive(:info)
        allow(ExceptionReporter).to receive(:call)

        described_class.perform_now(user.id)

        expect(Rails.logger).not_to have_received(:info).with("Successfully deleted user #{user.id}")
      end
    end

    context 'with retry configuration' do
      it 'does not retry on failure' do
        expect(described_class.get_sidekiq_options['retry']).to eq(false)
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

        expect(User.deleted_accounts.find_by(id: user.id)).to be_present
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
