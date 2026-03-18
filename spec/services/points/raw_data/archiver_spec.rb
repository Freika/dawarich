# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::Archiver do
  let(:user) { create(:user) }
  let(:archiver) { described_class.new }

  before do
    allow(PointsChannel).to receive(:broadcast_to)
  end

  describe '#archive_user' do
    let!(:old_points) do
      old_date = 3.months.ago.beginning_of_month
      create_list(:point, 5, user: user,
                            timestamp: old_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'archives old points' do
      expect { archiver.archive_user(user.id) }.to change(Points::RawDataArchive, :count).by(1)
    end

    it 'marks points as archived' do
      archiver.archive_user(user.id)

      expect(Point.where(raw_data_archived: true).count).to eq(5)
    end

    it 'keeps raw_data intact (does not clear yet)' do
      archiver.archive_user(user.id)
      Point.where(user: user).find_each do |point|
        expect(point.raw_data).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
      end
    end

    it 'returns correct stats' do
      result = archiver.archive_user(user.id)

      expect(result[:processed]).to be >= 1
      expect(result[:archived]).to eq(5)
      expect(result[:failed]).to eq(0)
    end

    it 'flags points in small batches' do
      archiver.archive_user(user.id)

      old_points.each(&:reload)
      expect(old_points.all?(&:raw_data_archived)).to be true
      expect(old_points.map(&:raw_data_archive_id).uniq.compact.size).to eq(1)
    end

    it 'does not archive recent points' do
      recent_point = create(:point, user: user,
                                    timestamp: 1.week.ago.to_i,
                                    raw_data: { lon: 13.4, lat: 52.5 })

      archiver.archive_user(user.id)

      expect(recent_point.reload.raw_data_archived).to be false
    end

    it 'does not archive points with empty raw_data' do
      empty_point = create(:point, user: user,
                                   timestamp: 3.months.ago.to_i,
                                   raw_data: {})

      archiver.archive_user(user.id)

      expect(empty_point.reload.raw_data_archived).to be false
    end

    context 'with points from multiple months' do
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

      it 'archives all eligible points' do
        archiver.archive_user(user.id)

        # 5 old_points + 3 june + 2 july = 10
        expect(Point.where(raw_data_archived: true).count).to eq(10)
      end
    end

    it 'stores min and max point IDs in metadata' do
      archiver.archive_user(user.id)

      archive = user.raw_data_archives.last
      expect(archive.metadata['min_point_id']).to eq(old_points.map(&:id).min)
      expect(archive.metadata['max_point_id']).to eq(old_points.map(&:id).max)
    end
  end

  describe '#archive_specific_month' do
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

    it 'attaches encrypted file' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = user.raw_data_archives.last
      expect(archive.file).to be_attached
      expect(archive.file.key).to match(%r{raw_data_archives/\d+/\d{4}/\d{2}/001\.jsonl\.gz\.enc})
      expect(archive.file.content_type).to eq('application/octet-stream')
    end

    it 'stores encryption metadata' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = user.raw_data_archives.last
      expect(archive.metadata['format_version']).to eq(2)
      expect(archive.metadata['encryption']).to eq('aes-256-gcm')
      expect(archive.metadata['content_checksum']).to be_present
    end

    it 'flags points in batches' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      june_points.each(&:reload)
      expect(june_points.all?(&:raw_data_archived)).to be true
    end
  end

  describe 'append-only architecture' do
    let(:test_date_utc) { 3.months.ago.utc.beginning_of_month }
    let!(:june_points_batch1) do
      create_list(:point, 2, user: user,
                            timestamp: test_date_utc.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'creates additional chunks for same month' do
      archiver.archive_specific_month(user.id, test_date_utc.year, test_date_utc.month)
      expect(Points::RawDataArchive.for_month(user.id, test_date_utc.year, test_date_utc.month).count).to eq(1)
      expect(Points::RawDataArchive.last.chunk_number).to eq(1)

      june_points_batch1.each(&:reload)
      expect(june_points_batch1.all?(&:raw_data_archived)).to be true

      mid_month = test_date_utc + 15.days
      create(:point, user: user, timestamp: mid_month.to_i, raw_data: { lon: 14.0, lat: 53.0 })
      create(:point, user: user, timestamp: (mid_month + 1.hour).to_i, raw_data: { lon: 14.0, lat: 53.0 })

      archiver.archive_specific_month(user.id, test_date_utc.year, test_date_utc.month)
      expect(Points::RawDataArchive.for_month(user.id, test_date_utc.year, test_date_utc.month).count).to eq(2)
      expect(Points::RawDataArchive.last.chunk_number).to eq(2)
    end
  end

  describe 'advisory locking' do
    let!(:june_points) do
      old_date = 3.months.ago.beginning_of_month
      create_list(:point, 2, user: user,
                            timestamp: old_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'prevents duplicate processing via archive_specific_month' do
      allow(ActiveRecord::Base).to receive(:with_advisory_lock).and_return(false)

      old_date = 3.months.ago.beginning_of_month
      expect do
        archiver.archive_specific_month(user.id, old_date.year, old_date.month)
      end.to raise_error(RuntimeError, /Could not acquire lock/)
    end
  end

  describe 'count validation' do
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

    it 'raises error when compression count mismatch occurs' do
      fake_compressor = instance_double(Points::RawData::ChunkCompressor)
      allow(Points::RawData::ChunkCompressor).to receive(:new).and_return(fake_compressor)

      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      3.times { |i| gz.puts({ id: i, raw_data: { test: 'data' } }.to_json) }
      gz.close

      allow(fake_compressor).to receive(:compress).and_return(
        { data: io.string.force_encoding(Encoding::ASCII_8BIT), count: 3 }
      )

      expect do
        archiver.archive_specific_month(user.id, test_date.year, test_date.month)
      end.to raise_error(StandardError, /count mismatch/)
    end

    it 'does not mark points as archived if count mismatch detected' do
      fake_compressor = instance_double(Points::RawData::ChunkCompressor)
      allow(Points::RawData::ChunkCompressor).to receive(:new).and_return(fake_compressor)

      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      3.times { |i| gz.puts({ id: i, raw_data: { test: 'data' } }.to_json) }
      gz.close

      allow(fake_compressor).to receive(:compress).and_return(
        { data: io.string.force_encoding(Encoding::ASCII_8BIT), count: 3 }
      )

      expect do
        archiver.archive_specific_month(user.id, test_date.year, test_date.month)
      end.to raise_error(StandardError)

      test_points.each(&:reload)
      expect(test_points.none?(&:raw_data_archived)).to be true
    end
  end

  describe 'archive content integrity' do
    let(:test_date) { 3.months.ago.beginning_of_month.utc }
    let!(:test_points) do
      create_list(:point, 3, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'stores valid encrypted, compressed JSONL data' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = user.raw_data_archives.last
      encrypted_content = archive.file.blob.download
      compressed_content = Points::RawData::Encryption.decrypt(encrypted_content)
      io = StringIO.new(compressed_content)
      gz = Zlib::GzipReader.new(io)
      archived_point_ids = gz.each_line.map { |line| JSON.parse(line)['id'] }
      gz.close

      expect(archived_point_ids.sort).to eq(test_points.map(&:id).sort)
    end

    it 'stores correct content checksum' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = user.raw_data_archives.last
      encrypted_content = archive.file.blob.download
      actual_checksum = Digest::SHA256.hexdigest(encrypted_content)

      expect(archive.metadata['content_checksum']).to eq(actual_checksum)
    end
  end
end
