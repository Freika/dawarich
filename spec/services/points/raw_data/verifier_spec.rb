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
      Points::RawDataArchive.last.tap { |a| a.update_column(:verified_at, nil) }
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
      end.not_to(change { archive.reload.verified_at })
    end

    it 'detects point count mismatch' do
      # Tamper with point count
      archive.update_column(:point_count, 999)

      expect do
        verifier.verify_specific_archive(archive.id)
      end.not_to(change { archive.reload.verified_at })
    end

    it 'detects checksum mismatch' do
      # Tamper with checksum
      archive.update_column(:point_ids_checksum, 'invalid')

      expect do
        verifier.verify_specific_archive(archive.id)
      end.not_to(change { archive.reload.verified_at })
    end

    it 'still verifies successfully when points are deleted from database' do
      # Force archive creation first
      archive_id = archive.id

      # Then delete one point from database
      points.first.destroy

      # Verification should still succeed - deleted points are acceptable
      # (users should be able to delete their data without failing archive verification)
      expect do
        verifier.verify_specific_archive(archive_id)
      end.to change { archive.reload.verified_at }.from(nil)
    end

    it 'detects raw_data mismatch between archive and database' do
      # Force archive creation first
      archive_id = archive.id

      # Then modify raw_data in database after archiving
      points.first.update_column(:raw_data, { lon: 999.0, lat: 999.0 })

      expect do
        verifier.verify_specific_archive(archive_id)
      end.not_to(change { archive.reload.verified_at })
    end

    it 'verifies raw_data matches between archive and database' do
      # Ensure data hasn't changed
      expect(points.first.raw_data).to eq({ 'lon' => 13.4, 'lat' => 52.5 })

      verifier.verify_specific_archive(archive.id)

      expect(archive.reload.verified_at).to be_present
    end

    it 'passes verification when raw_data was already cleared after archiving' do
      archive_id = archive.id

      Point.where(id: points.map(&:id)).update_all(raw_data: {})

      expect do
        verifier.verify_specific_archive(archive_id)
      end.to change { archive.reload.verified_at }.from(nil)
    end

    it 'does not bump verified_at when re-verifying an already verified archive' do
      original = 10.days.ago.change(usec: 0)
      archive.update_column(:verified_at, original)

      verifier.verify_specific_archive(archive.id)

      expect(archive.reload.verified_at).to eq(original)
    end

    it 'unsets verified_at when a previously verified archive fails re-verification' do
      archive.update_column(:verified_at, 10.days.ago)
      archive.update_column(:point_ids_checksum, 'invalid')

      verifier.verify_specific_archive(archive.id)

      expect(archive.reload.verified_at).to be_nil
    end

    it 'keeps verified_at when a re-check fails only due to a download error' do
      archive.update_column(:verified_at, 10.days.ago)
      allow(Points::RawDataArchive).to receive(:find).with(archive.id).and_return(archive)
      allow(archive.file.blob).to receive(:download).and_raise(StandardError, 'timeout')

      verifier.verify_specific_archive(archive.id)

      expect(archive.reload.verified_at).to be_present
    end

    it 'unsets verified_at when a re-check fails to decrypt the archive' do
      archive.update_column(:verified_at, 10.days.ago)
      allow(Points::RawData::Encryption)
        .to receive(:decrypt_if_needed).and_raise(OpenSSL::Cipher::CipherError, 'bad decrypt')

      verifier.verify_specific_archive(archive.id)

      expect(archive.reload.verified_at).to be_nil
    end

    it 'reports how many points were already cleared when a verified archive fails re-check' do
      archive.update_column(:verified_at, 10.days.ago)
      archive.update_column(:point_ids_checksum, 'invalid')
      Point.where(id: points.map(&:id)).update_all(raw_data: {}, raw_data_archive_id: archive.id)

      expect(ExceptionReporter).to receive(:call).with(anything, %r{5/5 linked points already cleared})

      verifier.verify_specific_archive(archive.id)
    end

    it 'skips raw_data comparison for points re-archived into a different archive' do
      archive_id = archive.id
      other_archive = create(:points_raw_data_archive, user: user, year: 2020, month: 1)

      points.first.update_columns(
        raw_data: { 'mutated' => true }, raw_data_archive_id: other_archive.id
      )

      expect do
        verifier.verify_specific_archive(archive_id)
      end.to change { archive.reload.verified_at }.from(nil)
    end
  end

  describe 'encryption support' do
    let(:test_date) { 3.months.ago.beginning_of_month.utc }
    let!(:points) do
      create_list(:point, 3, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    let(:archive) do
      archiver = Points::RawData::Archiver.new
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)
      Points::RawDataArchive.last
    end

    it 'verifies encrypted archives (format_version 2)' do
      expect(archive.metadata['format_version']).to eq(2)
      expect(archive.metadata['encryption']).to eq('aes-256-gcm')

      verifier.verify_specific_archive(archive.id)
      archive.reload

      expect(archive.verified_at).to be_present
    end

    it 'detects content checksum tampering and unsets verified_at' do
      archive.metadata['content_checksum'] = 'tampered_checksum'
      archive.save!

      expect do
        verifier.verify_specific_archive(archive.id)
      end.to change { archive.reload.verified_at }.to(nil)
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
      user.raw_data_archives.update_all(verified_at: nil)
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
      user.raw_data_archives.update_all(verified_at: nil)
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

      # Try to verify again with a new verifier instance
      new_verifier = Points::RawData::Verifier.new
      result = new_verifier.call

      expect(result[:verified]).to eq(0)
      expect(result[:failed]).to eq(0)
    end
  end

  describe 'metric emissions' do
    let(:test_date) { 3.months.ago.beginning_of_month.utc }

    let(:archive) do
      create_list(:point, 3, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })

      archiver = Points::RawData::Archiver.new
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)
      Points::RawDataArchive.last
    end

    it 'increments operations_total with verify/success on successful verification' do
      expect do
        verifier.verify_specific_archive(archive.id)
      end.to increment_yabeda_counter(Yabeda.dawarich_archive.operations_total)
        .with_tags(operation: 'verify', status: 'success')
    end

    it 'measures verification_duration_seconds with success status' do
      expect do
        verifier.verify_specific_archive(archive.id)
      end.to measure_yabeda_histogram(Yabeda.dawarich_archive.verification_duration_seconds)
        .with_tags(status: 'success')
    end

    context 'when verification fails' do
      before { archive.update_column(:point_count, 999) }

      it 'increments operations_total with verify/failure' do
        expect do
          verifier.verify_specific_archive(archive.id)
        end.to increment_yabeda_counter(Yabeda.dawarich_archive.operations_total)
          .with_tags(operation: 'verify', status: 'failure')
      end

      it 'measures verification_duration_seconds with failure status' do
        expect do
          verifier.verify_specific_archive(archive.id)
        end.to measure_yabeda_histogram(Yabeda.dawarich_archive.verification_duration_seconds)
          .with_tags(status: 'failure')
      end

      it 'increments verification_failures_total with check tag' do
        expect do
          verifier.verify_specific_archive(archive.id)
        end.to increment_yabeda_counter(Yabeda.dawarich_archive.verification_failures_total)
      end
    end
  end
end
