# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::Archiver do
  let(:user) { create(:user) }
  let(:archiver) { described_class.new }

  before do
    allow(PointsChannel).to receive(:broadcast_to)
  end

  describe '#call' do
    context 'when archival is disabled' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('false')
      end

      it 'returns early without processing' do
        result = archiver.call

        expect(result).to eq({ processed: 0, archived: 0, failed: 0 })
      end
    end

    context 'when archival is enabled' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
      end

      let!(:old_points) do
        # Create points 3 months ago (definitely older than 2 month lag)
        old_date = 3.months.ago.beginning_of_month
        create_list(:point, 5, user: user,
                              timestamp: old_date.to_i,
                              raw_data: { lon: 13.4, lat: 52.5 })
      end

      it 'archives old points' do
        expect { archiver.call }.to change(Points::RawDataArchive, :count).by(1)
      end

      it 'marks points as archived' do
        archiver.call

        expect(Point.where(raw_data_archived: true).count).to eq(5)
      end

      it 'keeps raw_data intact (does not clear yet)' do
        archiver.call
        Point.where(user: user).find_each do |point|
          expect(point.raw_data).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
        end
      end

      it 'returns correct stats' do
        result = archiver.call

        expect(result[:processed]).to eq(1)
        expect(result[:archived]).to eq(5)
        expect(result[:failed]).to eq(0)
      end
    end

    context 'with points from multiple months' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
      end

      let!(:june_points) do
        june_date = 4.months.ago.beginning_of_month
        create_list(:point, 3, user: user,
                              timestamp: june_date.to_i,
                              raw_data: { lon: 13.4, lat: 52.5 })
      end

      let!(:july_points) do
        july_date = 3.months.ago.beginning_of_month
        create_list(:point, 2, user: user,
                              timestamp: july_date.to_i,
                              raw_data: { lon: 14.0, lat: 53.0 })
      end

      it 'creates separate archives for each month' do
        expect { archiver.call }.to change(Points::RawDataArchive, :count).by(2)
      end

      it 'archives all points' do
        archiver.call
        expect(Point.where(raw_data_archived: true).count).to eq(5)
      end
    end
  end

  describe '#archive_specific_month' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
    end

    let(:test_date) { 3.months.ago.beginning_of_month.utc }
    let!(:june_points) do
      create_list(:point, 3, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'archives specific month' do
      expect do
        archiver.archive_specific_month(user.id, test_date.year, test_date.month)
      end.to change(Points::RawDataArchive, :count).by(1)
    end

    it 'creates archive with correct metadata' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = user.raw_data_archives.last

      expect(archive.user_id).to eq(user.id)
      expect(archive.year).to eq(test_date.year)
      expect(archive.month).to eq(test_date.month)
      expect(archive.point_count).to eq(3)
      expect(archive.chunk_number).to eq(1)
    end

    it 'attaches compressed file' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = user.raw_data_archives.last
      expect(archive.file).to be_attached
      expect(archive.file.key).to match(%r{raw_data_archives/\d+/\d{4}/\d{2}/001\.jsonl\.gz})
    end
  end

  describe 'append-only architecture' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
    end

    # Use UTC from the start to avoid timezone issues
    let(:test_date_utc) { 3.months.ago.utc.beginning_of_month }
    let!(:june_points_batch1) do
      create_list(:point, 2, user: user,
                            timestamp: test_date_utc.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'creates additional chunks for same month' do
      # First archival
      archiver.archive_specific_month(user.id, test_date_utc.year, test_date_utc.month)
      expect(Points::RawDataArchive.for_month(user.id, test_date_utc.year, test_date_utc.month).count).to eq(1)
      expect(Points::RawDataArchive.last.chunk_number).to eq(1)

      # Verify first batch is archived
      june_points_batch1.each(&:reload)
      expect(june_points_batch1.all?(&:raw_data_archived)).to be true

      # Add more points for same month (retrospective import)
      # Use unique timestamps to avoid uniqueness validation errors
      mid_month = test_date_utc + 15.days
      june_points_batch2 = [
        create(:point, user: user, timestamp: mid_month.to_i, raw_data: { lon: 14.0, lat: 53.0 }),
        create(:point, user: user, timestamp: (mid_month + 1.hour).to_i, raw_data: { lon: 14.0, lat: 53.0 })
      ]

      # Verify second batch exists and is not archived
      expect(june_points_batch2.all? { |p| !p.raw_data_archived }).to be true

      # Second archival should create chunk 2
      archiver.archive_specific_month(user.id, test_date_utc.year, test_date_utc.month)
      expect(Points::RawDataArchive.for_month(user.id, test_date_utc.year, test_date_utc.month).count).to eq(2)
      expect(Points::RawDataArchive.last.chunk_number).to eq(2)
    end
  end

  describe 'advisory locking' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
    end

    let!(:june_points) do
      old_date = 3.months.ago.beginning_of_month
      create_list(:point, 2, user: user,
                            timestamp: old_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'prevents duplicate processing with advisory locks' do
      # Simulate lock couldn't be acquired (returns nil/false)
      allow(ActiveRecord::Base).to receive(:with_advisory_lock).and_return(false)

      result = archiver.call
      expect(result[:processed]).to eq(0)
      expect(result[:failed]).to eq(0)
    end
  end

  describe 'count validation (P0 implementation)' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
    end

    let(:test_date) { 3.months.ago.beginning_of_month.utc }
    let!(:test_points) do
      create_list(:point, 5, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'validates compression count matches expected count' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = user.raw_data_archives.last
      expect(archive.point_count).to eq(5)
      expect(archive.metadata['expected_count']).to eq(5)
      expect(archive.metadata['actual_count']).to eq(5)
    end

    it 'stores both expected and actual counts in metadata' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = user.raw_data_archives.last
      expect(archive.metadata).to have_key('expected_count')
      expect(archive.metadata).to have_key('actual_count')
      expect(archive.metadata['expected_count']).to eq(archive.metadata['actual_count'])
    end

    it 'raises error when compression count mismatch occurs' do
      # Create proper gzip compressed data with only 3 points instead of 5
      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      3.times do |i|
        gz.puts({ id: i, raw_data: { test: 'data' } }.to_json)
      end
      gz.close
      fake_compressed_data = io.string.force_encoding(Encoding::ASCII_8BIT)

      # Mock ChunkCompressor to return mismatched count
      fake_compressor = instance_double(Points::RawData::ChunkCompressor)
      allow(Points::RawData::ChunkCompressor).to receive(:new).and_return(fake_compressor)
      allow(fake_compressor).to receive(:compress).and_return(
        { data: fake_compressed_data, count: 3 }  # Returning 3 instead of 5
      )

      expect do
        archiver.archive_specific_month(user.id, test_date.year, test_date.month)
      end.to raise_error(StandardError, /Archive count mismatch/)
    end

    it 'does not mark points as archived if count mismatch detected' do
      # Create proper gzip compressed data with only 3 points instead of 5
      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      3.times do |i|
        gz.puts({ id: i, raw_data: { test: 'data' } }.to_json)
      end
      gz.close
      fake_compressed_data = io.string.force_encoding(Encoding::ASCII_8BIT)

      # Mock ChunkCompressor to return mismatched count
      fake_compressor = instance_double(Points::RawData::ChunkCompressor)
      allow(Points::RawData::ChunkCompressor).to receive(:new).and_return(fake_compressor)
      allow(fake_compressor).to receive(:compress).and_return(
        { data: fake_compressed_data, count: 3 }
      )

      expect do
        archiver.archive_specific_month(user.id, test_date.year, test_date.month)
      end.to raise_error(StandardError)

      # Verify points are NOT marked as archived
      test_points.each(&:reload)
      expect(test_points.none?(&:raw_data_archived)).to be true
    end
  end

  describe 'immediate verification (P0 implementation)' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
    end

    let(:test_date) { 3.months.ago.beginning_of_month.utc }
    let!(:test_points) do
      create_list(:point, 3, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'runs immediate verification after archiving' do
      # Spy on the verify_archive_immediately method
      allow(archiver).to receive(:verify_archive_immediately).and_call_original

      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      expect(archiver).to have_received(:verify_archive_immediately)
    end

    it 'rolls back archive if immediate verification fails' do
      # Mock verification to fail
      allow(archiver).to receive(:verify_archive_immediately).and_return(
        { success: false, error: 'Test verification failure' }
      )

      expect do
        archiver.archive_specific_month(user.id, test_date.year, test_date.month)
      end.to raise_error(StandardError, /Archive verification failed/)

      # Verify archive was destroyed
      expect(Points::RawDataArchive.count).to eq(0)

      # Verify points are NOT marked as archived
      test_points.each(&:reload)
      expect(test_points.none?(&:raw_data_archived)).to be true
    end

    it 'completes successfully when immediate verification passes' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      # Verify archive was created
      expect(Points::RawDataArchive.count).to eq(1)

      # Verify points ARE marked as archived
      test_points.each(&:reload)
      expect(test_points.all?(&:raw_data_archived)).to be true
    end

    it 'validates point IDs checksum during immediate verification' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = user.raw_data_archives.last
      expect(archive.point_ids_checksum).to be_present

      # Decompress and verify the archived point IDs match
      compressed_content = archive.file.blob.download
      io = StringIO.new(compressed_content)
      gz = Zlib::GzipReader.new(io)
      archived_point_ids = []

      gz.each_line do |line|
        data = JSON.parse(line)
        archived_point_ids << data['id']
      end
      gz.close

      expect(archived_point_ids.sort).to eq(test_points.map(&:id).sort)
    end
  end
end
