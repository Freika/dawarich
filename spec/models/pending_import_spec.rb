# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PendingImport do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:pending_import)).to be_valid
    end

    it 'is invalid without original_filename' do
      expect(build(:pending_import, original_filename: nil)).not_to be_valid
    end

    it 'is invalid without origin' do
      expect(build(:pending_import, origin: nil)).not_to be_valid
    end

    it 'is invalid without expires_at' do
      expect(build(:pending_import, expires_at: nil)).not_to be_valid
    end

    it 'auto-generates claim_ticket as a UUID' do
      pending = create(:pending_import)
      expect(pending.claim_ticket).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'enforces uniqueness of claim_ticket at the DB level' do
      pending = create(:pending_import)
      duplicate = build(:pending_import, claim_ticket: pending.claim_ticket)
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '.claimable' do
    let!(:fresh_unclaimed) { create(:pending_import, expires_at: 12.hours.from_now, claimed_at: nil) }
    let!(:expired_unclaimed) { create(:pending_import, expires_at: 1.hour.ago, claimed_at: nil) }
    let!(:claimed) { create(:pending_import, expires_at: 12.hours.from_now, claimed_at: 5.minutes.ago) }
    let!(:claimed_and_expired) { create(:pending_import, expires_at: 1.hour.ago, claimed_at: 5.minutes.ago) }

    it 'includes unclaimed, unexpired records' do
      expect(described_class.claimable).to include(fresh_unclaimed)
    end

    it 'excludes expired records' do
      expect(described_class.claimable).not_to include(expired_unclaimed)
    end

    it 'excludes already-claimed records' do
      expect(described_class.claimable).not_to include(claimed)
    end
  end

  describe '.expired' do
    let!(:expired_record) { create(:pending_import, expires_at: 1.hour.ago) }
    let!(:fresh_record) { create(:pending_import, expires_at: 1.hour.from_now) }

    it 'includes records past their expires_at' do
      expect(described_class.expired).to include(expired_record)
    end

    it 'excludes records still valid' do
      expect(described_class.expired).not_to include(fresh_record)
    end
  end

  describe 'file attachment' do
    let(:pending) { create(:pending_import, :with_file) }

    it 'has an attached file' do
      expect(pending.file).to be_attached
    end

    it 'preserves the file content' do
      expect(pending.file.download.bytesize).to be > 0
    end
  end
end
