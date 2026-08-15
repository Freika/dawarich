# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Import deletion failure leaves a recoverable status' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, status: :completed) }

  context 'when the destroy service raises' do
    before do
      destroy_service = instance_double(Imports::Destroy)
      allow(Imports::Destroy).to receive(:new).and_return(destroy_service)
      allow(destroy_service).to receive(:call).and_raise(ActiveRecord::StatementInvalid, 'canceling statement')
    end

    it 're-raises the error so the job can retry' do
      expect { Imports::DestroyJob.perform_now(import.id) }
        .to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'does not leave the import stuck in deleting' do
      begin
        Imports::DestroyJob.perform_now(import.id)
      rescue ActiveRecord::StatementInvalid
        nil
      end

      expect(import.reload).to be_failed
    end
  end

  context 'when the import is already stuck in deleting' do
    let(:import) { create(:import, user: user, status: :deleting) }

    it 'can be re-enqueued and deletes the import' do
      Imports::DestroyJob.perform_now(import.id)

      expect(Import.find_by(id: import.id)).to be_nil
    end
  end
end
