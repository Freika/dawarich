# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::Verifier do
  let(:user) { create(:user) }
  let(:verifier) { described_class.new }

  before do
    allow(PointsChannel).to receive(:broadcast_to)
  end

  describe '#verify_specific_archive' do
    let(:test_date) { 3.months.ago.beginning_of_month.utc }
    let!(:points) do
      create_list(:point, 5, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    let(:archive) do
      # Create archive
      archiver = Points::RawData::Archiver.new
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)
      Points::RawDataArchive.last
    end

    it 'verifies a valid archive successfully' do
      expect(archive.verified_at).to be_nil

      verifier.verify_specific_archive(archive.id)
      archive.reload

      expect(archive.verified_at).to be_present
    end

    it 'detects missing file' do
      archive.file.purge
      archive.reload

      expect do
        verifier.verify_specific_archive(archive.id)
      end.not_to change { archive.reload.verified_at }
    end

    it 'detects point count mismatch' do
      # Tamper with point count
      archive.update_column(:point_count, 999)

      expect do
        verifier.verify_specific_archive(archive.id)
      end.not_to change { archive.reload.verified_at }
    end

    it 'detects checksum mismatch' do
      # Tamper with checksum
      archive.update_column(:point_ids_checksum, 'invalid')

      expect do
        verifier.verify_specific_archive(archive.id)
      end.not_to change { archive.reload.verified_at }
    end

    it 'detects deleted points' do
      # Delete one point from database
      points.first.destroy

      expect do
        verifier.verify_specific_archive(archive.id)
      end.not_to change { archive.reload.verified_at }
    end

    it 'detects raw_data mismatch between archive and database' do
      # Modify raw_data in database after archiving
      points.first.update_column(:raw_data, { lon: 999.0, lat: 999.0 })

      expect do
        verifier.verify_specific_archive(archive.id)
      end.not_to change { archive.reload.verified_at }
    end

    it 'verifies raw_data matches between archive and database' do
      # Ensure data hasn't changed
      expect(points.first.raw_data).to eq({ 'lon' => 13.4, 'lat' => 52.5 })

      verifier.verify_specific_archive(archive.id)

      expect(archive.reload.verified_at).to be_present
    end
  end

  describe '#verify_month' do
    let(:test_date) { 3.months.ago.beginning_of_month.utc }

    before do
      # Create points
      create_list(:point, 5, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })

      # Archive them
      archiver = Points::RawData::Archiver.new
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)
    end

    it 'verifies all archives for a month' do
      expect(Points::RawDataArchive.where(verified_at: nil).count).to eq(1)

      verifier.verify_month(user.id, test_date.year, test_date.month)

      expect(Points::RawDataArchive.where(verified_at: nil).count).to eq(0)
    end
  end

  describe '#call' do
    let(:test_date) { 3.months.ago.beginning_of_month.utc }

    before do
      # Create points and archive
      create_list(:point, 5, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })

      archiver = Points::RawData::Archiver.new
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)
    end

    it 'verifies all unverified archives' do
      expect(Points::RawDataArchive.where(verified_at: nil).count).to eq(1)

      result = verifier.call

      expect(result[:verified]).to eq(1)
      expect(result[:failed]).to eq(0)
      expect(Points::RawDataArchive.where(verified_at: nil).count).to eq(0)
    end

    it 'reports failures' do
      # Tamper with archive
      Points::RawDataArchive.last.update_column(:point_count, 999)

      result = verifier.call

      expect(result[:verified]).to eq(0)
      expect(result[:failed]).to eq(1)
    end

    it 'skips already verified archives' do
      # Verify once
      verifier.call

      # Try to verify again
      result = verifier.call

      expect(result[:verified]).to eq(0)
      expect(result[:failed]).to eq(0)
    end
  end
end
