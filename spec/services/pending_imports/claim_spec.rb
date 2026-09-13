# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PendingImports::Claim do
  let(:user) { create(:user) }
  let(:pending) { create(:pending_import, :with_file, original_filename: 'records.zip') }

  describe '#call' do
    it 'creates an Import owned by the user' do
      expect { described_class.new(pending, user).call }.to change(user.imports, :count).by(1)
    end

    it 'returns the created Import' do
      result = described_class.new(pending, user).call
      expect(result).to be_a(Import)
      expect(result.user).to eq(user)
    end

    it 'sets the Import name from the original_filename' do
      result = described_class.new(pending, user).call
      expect(result.name).to eq('records.zip')
    end

    it 'marks pending_import.claimed_at' do
      described_class.new(pending, user).call
      expect(pending.reload.claimed_at).to be_within(5.seconds).of(Time.current)
    end

    it 'sets pending_import.claimed_by_user_id' do
      described_class.new(pending, user).call
      expect(pending.reload.claimed_by_user_id).to eq(user.id)
    end
  end

  describe 'single-use enforcement' do
    it 'returns nil and creates no Import when the ticket was already claimed' do
      described_class.new(pending, user).call

      other_user = create(:user)
      result = nil
      expect { result = described_class.new(pending.reload, other_user).call }
        .not_to change(Import, :count)
      expect(result).to be_nil
    end

    it 'returns nil for an expired ticket' do
      pending.update!(expires_at: 1.hour.ago)

      expect(described_class.new(pending, user).call).to be_nil
      expect(pending.reload.claimed_at).to be_nil
    end
  end

  describe 'blob reassignment' do
    it 'reassigns the same blob to the new Import (no copy)' do
      original_blob_id = pending.file.blob.id
      import = described_class.new(pending, user).call
      expect(import.file.blob.id).to eq(original_blob_id)
    end

    it 'leaves the Import file intact after the PendingImport is destroyed' do
      import = described_class.new(pending, user).call
      pending.destroy
      expect(import.reload.file).to be_attached
      expect(import.file.download.bytesize).to be > 0
    end
  end

  describe 'import processing pipeline' do
    it 'enqueues Import::ProcessJob via Import after_commit' do
      expect { described_class.new(pending, user).call }.to have_enqueued_job(Import::ProcessJob)
    end
  end

  describe 'name collision handling' do
    it 'generates a unique name when the user already has an import with that name' do
      create(:import, user: user, name: 'records.zip')
      result = described_class.new(pending, user).call
      expect(result.name).to match(/\Arecords_\d{8}_\d{6}\.zip\z/)
    end
  end

  describe 'transaction safety' do
    it 'does not mark pending_import as claimed if Import save fails' do
      allow_any_instance_of(Import).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
      expect { described_class.new(pending, user).call }.to raise_error(ActiveRecord::RecordInvalid)
      expect(pending.reload.claimed_at).to be_nil
    end
  end
end
