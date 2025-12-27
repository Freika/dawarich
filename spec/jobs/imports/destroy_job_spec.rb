# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::DestroyJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }
    let(:import) { create(:import, user: user, status: :completed) }

    describe 'queue configuration' do
      it 'uses the default queue' do
        expect(described_class.queue_name).to eq('default')
      end
    end

    context 'when import exists' do
      before do
        create_list(:point, 3, user: user, import: import)
      end

      it 'changes import status to deleting and deletes it' do
        expect(import).not_to be_deleting

        import_id = import.id
        described_class.perform_now(import_id)

        expect(Import.find_by(id: import_id)).to be_nil
      end

      it 'calls the Imports::Destroy service' do
        destroy_service = instance_double(Imports::Destroy)
        allow(Imports::Destroy).to receive(:new).with(user, import).and_return(destroy_service)
        allow(destroy_service).to receive(:call)

        described_class.perform_now(import.id)

        expect(Imports::Destroy).to have_received(:new).with(user, import)
        expect(destroy_service).to have_received(:call)
      end

      it 'broadcasts status update to the user' do
        allow(ImportsChannel).to receive(:broadcast_to)

        described_class.perform_now(import.id)

        expect(ImportsChannel).to have_received(:broadcast_to).with(
          user,
          hash_including(
            action: 'status_update',
            import: hash_including(
              id: import.id,
              status: 'deleting'
            )
          )
        ).at_least(:once)
      end

      it 'broadcasts deletion complete to the user' do
        allow(ImportsChannel).to receive(:broadcast_to)

        described_class.perform_now(import.id)

        expect(ImportsChannel).to have_received(:broadcast_to).with(
          user,
          hash_including(
            action: 'delete',
            import: hash_including(id: import.id)
          )
        ).at_least(:once)
      end

      it 'broadcasts both status update and deletion messages' do
        allow(ImportsChannel).to receive(:broadcast_to)

        described_class.perform_now(import.id)

        expect(ImportsChannel).to have_received(:broadcast_to).twice
      end

      it 'deletes the import and its points' do
        import_id = import.id
        point_ids = import.points.pluck(:id)

        described_class.perform_now(import_id)

        expect(Import.find_by(id: import_id)).to be_nil
        expect(Point.where(id: point_ids)).to be_empty
      end
    end

    context 'when import does not exist' do
      let(:non_existent_id) { 999_999 }

      it 'does not raise an error' do
        expect { described_class.perform_now(non_existent_id) }.not_to raise_error
      end

      it 'does not call the Imports::Destroy service' do
        expect(Imports::Destroy).not_to receive(:new)

        described_class.perform_now(non_existent_id)
      end

      it 'does not broadcast any messages' do
        expect(ImportsChannel).not_to receive(:broadcast_to)

        described_class.perform_now(non_existent_id)
      end

      it 'returns early without logging' do
        allow(Rails.logger).to receive(:warn)

        described_class.perform_now(non_existent_id)

        expect(Rails.logger).not_to have_received(:warn)
      end
    end

    context 'when import is deleted during job execution' do
      it 'handles RecordNotFound gracefully' do
        allow(Import).to receive(:find_by).with(id: import.id).and_return(import)
        allow(import).to receive(:deleting!).and_raise(ActiveRecord::RecordNotFound)

        expect { described_class.perform_now(import.id) }.not_to raise_error
      end

      it 'logs a warning when RecordNotFound is raised' do
        allow(Import).to receive(:find_by).with(id: import.id).and_return(import)
        allow(import).to receive(:deleting!).and_raise(ActiveRecord::RecordNotFound)
        allow(Rails.logger).to receive(:warn)

        described_class.perform_now(import.id)

        expect(Rails.logger).to have_received(:warn).with(/Import #{import.id} not found/)
      end
    end

    context 'when broadcast fails' do
      before do
        allow(ImportsChannel).to receive(:broadcast_to).and_raise(StandardError, 'Broadcast error')
      end

      it 'allows the error to propagate' do
        expect { described_class.perform_now(import.id) }.to raise_error(StandardError, 'Broadcast error')
      end
    end

    context 'when Imports::Destroy service fails' do
      before do
        allow_any_instance_of(Imports::Destroy).to receive(:call).and_raise(StandardError, 'Destroy failed')
      end

      it 'allows the error to propagate' do
        expect { described_class.perform_now(import.id) }.to raise_error(StandardError, 'Destroy failed')
      end

      it 'has already set status to deleting before service is called' do
        expect do
          described_class.perform_now(import.id)
        rescue StandardError
          StandardError
        end.to change { import.reload.status }.to('deleting')
      end
    end

    context 'with multiple imports for different users' do
      let(:user2) { create(:user) }
      let(:import2) { create(:import, user: user2, status: :completed) }

      it 'only broadcasts to the correct user' do
        expect(ImportsChannel).to receive(:broadcast_to).with(user, anything).twice
        expect(ImportsChannel).not_to receive(:broadcast_to).with(user2, anything)

        described_class.perform_now(import.id)
      end
    end

    context 'job enqueuing' do
      it 'can be enqueued' do
        expect do
          described_class.perform_later(import.id)
        end.to have_enqueued_job(described_class).with(import.id)
      end

      it 'can be performed later with correct arguments' do
        expect do
          described_class.perform_later(import.id)
        end.to have_enqueued_job(described_class).on_queue('default').with(import.id)
      end
    end
  end
end
