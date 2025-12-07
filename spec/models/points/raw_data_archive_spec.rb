# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawDataArchive, type: :model do
  let(:user) { create(:user) }
  subject(:archive) { build(:points_raw_data_archive, user: user) }

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:points).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:year) }
    it { is_expected.to validate_presence_of(:month) }
    it { is_expected.to validate_presence_of(:chunk_number) }
    it { is_expected.to validate_presence_of(:point_count) }
    it { is_expected.to validate_presence_of(:point_ids_checksum) }

    it { is_expected.to validate_numericality_of(:year).is_greater_than(1970).is_less_than(2100) }
    it { is_expected.to validate_numericality_of(:month).is_greater_than_or_equal_to(1).is_less_than_or_equal_to(12) }
    it { is_expected.to validate_numericality_of(:chunk_number).is_greater_than(0) }

  end

  describe 'scopes' do
    let!(:recent_archive) { create(:points_raw_data_archive, user: user, year: 2024, month: 5, archived_at: 1.day.ago) }
    let!(:old_archive) { create(:points_raw_data_archive, user: user, year: 2023, month: 5, archived_at: 2.years.ago) }

    describe '.recent' do
      it 'returns archives from last 30 days' do
        expect(described_class.recent).to include(recent_archive)
        expect(described_class.recent).not_to include(old_archive)
      end
    end

    describe '.old' do
      it 'returns archives older than 1 year' do
        expect(described_class.old).to include(old_archive)
        expect(described_class.old).not_to include(recent_archive)
      end
    end

    describe '.for_month' do
      let!(:june_archive) { create(:points_raw_data_archive, user: user, year: 2024, month: 6, chunk_number: 1) }
      let!(:june_archive_2) { create(:points_raw_data_archive, user: user, year: 2024, month: 6, chunk_number: 2) }
      let!(:july_archive) { create(:points_raw_data_archive, user: user, year: 2024, month: 7, chunk_number: 1) }

      it 'returns archives for specific month ordered by chunk number' do
        result = described_class.for_month(user.id, 2024, 6)
        expect(result.map(&:chunk_number)).to eq([1, 2])
        expect(result).to include(june_archive, june_archive_2)
        expect(result).not_to include(july_archive)
      end
    end
  end

  describe '#month_display' do
    it 'returns formatted month and year' do
      archive = build(:points_raw_data_archive, year: 2024, month: 6)
      expect(archive.month_display).to eq('June 2024')
    end
  end

  describe '#filename' do
    it 'generates correct filename with directory structure' do
      archive = build(:points_raw_data_archive, user_id: 123, year: 2024, month: 6, chunk_number: 5)
      expect(archive.filename).to eq('raw_data_archives/123/2024/06/005.jsonl.gz')
    end
  end

  describe '#size_mb' do
    it 'returns 0 when no file attached' do
      archive = build(:points_raw_data_archive)
      expect(archive.size_mb).to eq(0)
    end

    it 'returns size in MB when file is attached' do
      archive = create(:points_raw_data_archive, user: user)
      # Mock file with 2MB size
      allow(archive.file.blob).to receive(:byte_size).and_return(2 * 1024 * 1024)
      expect(archive.size_mb).to eq(2.0)
    end
  end
end
