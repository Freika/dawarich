# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PendingImports::CleanupJob do
  it 'runs on the low_priority queue' do
    expect(described_class.new.queue_name).to eq('low_priority')
  end

  describe '#perform' do
    it 'destroys expired unclaimed pending imports' do
      expired = create(:pending_import, :with_file, expires_at: 1.day.ago)
      fresh = create(:pending_import, :with_file, expires_at: 1.day.from_now)

      described_class.perform_now

      expect(PendingImport.exists?(expired.id)).to be false
      expect(PendingImport.exists?(fresh.id)).to be true
    end

    it 'purges the blobs of expired pending imports' do
      expired = create(:pending_import, :with_file, expires_at: 1.day.ago)
      blob = expired.file.blob
      described_class.perform_now
      expect(ActiveStorage::Blob.exists?(blob.id)).to be false
    end
  end

  describe 'orphaned blob purge' do
    it 'purges the blob when the claiming Import was deleted before the sweep' do
      user = create(:user)
      pending = create(:pending_import, :with_file)
      import = PendingImports::Claim.new(pending, user).call
      blob = pending.file.blob

      import.destroy
      pending.update!(claimed_at: 8.days.ago)

      perform_enqueued_jobs { described_class.perform_now }

      expect(PendingImport.exists?(pending.id)).to be false
      expect(ActiveStorage::Blob.exists?(blob.id)).to be false
    end

    it 'keeps the blob while the claiming Import still references it' do
      user = create(:user)
      pending = create(:pending_import, :with_file)
      import = PendingImports::Claim.new(pending, user).call
      blob = pending.file.blob
      pending.update!(claimed_at: 8.days.ago)

      perform_enqueued_jobs { described_class.perform_now }

      expect(ActiveStorage::Blob.exists?(blob.id)).to be true
      expect(import.reload.file).to be_attached
    end
  end

  describe 'claimed-old purge' do
    it 'destroys pending imports claimed more than 7 days ago' do
      old = create(:pending_import, :with_file)
      old.update!(claimed_at: 8.days.ago, claimed_by_user_id: create(:user).id)

      described_class.perform_now

      expect(PendingImport.exists?(old.id)).to be false
    end

    it 'leaves pending imports claimed less than 7 days ago intact' do
      recent = create(:pending_import, :with_file)
      recent.update!(claimed_at: 3.days.ago, claimed_by_user_id: create(:user).id)

      described_class.perform_now

      expect(PendingImport.exists?(recent.id)).to be true
    end
  end

  describe 'blob safety (critical regression)' do
    it 'does NOT purge the user Import blob when a claimed pending_import is destroyed' do
      user = create(:user)
      pending = create(:pending_import, :with_file)
      user_import = PendingImports::Claim.new(pending, user).call
      pending.update!(claimed_at: 8.days.ago)

      blob_id = user_import.file.blob.id

      described_class.perform_now

      expect(user_import.reload.file).to be_attached
      expect(ActiveStorage::Blob.exists?(blob_id)).to be true
      expect(user_import.file.download.bytesize).to be > 0
    end
  end
end
