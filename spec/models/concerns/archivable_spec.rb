# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Archivable, type: :model do
  let(:user) { create(:user) }
  let(:point) { create(:point, user: user, raw_data: { lon: 13.4, lat: 52.5 }) }

  describe 'associations and scopes' do
    it { expect(point).to belong_to(:raw_data_archive).optional }

    describe 'scopes' do
      let!(:archived_point) { create(:point, user: user, raw_data_archived: true) }
      let!(:not_archived_point) { create(:point, user: user, raw_data_archived: false) }

      it '.archived returns archived points' do
        expect(Point.archived).to include(archived_point)
        expect(Point.archived).not_to include(not_archived_point)
      end

      it '.not_archived returns non-archived points' do
        expect(Point.not_archived).to include(not_archived_point)
        expect(Point.not_archived).not_to include(archived_point)
      end
    end
  end

  describe '#raw_data_with_archive' do
    context 'when raw_data is present in database' do
      it 'returns raw_data from database' do
        expect(point.raw_data_with_archive).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
      end
    end

    context 'when raw_data is archived' do
      let(:archive) { create(:points_raw_data_archive, user: user) }
      let(:archived_point) do
        create(:point, user: user, raw_data: nil, raw_data_archived: true, raw_data_archive: archive)
      end

      before do
        # Mock archive file content with this specific point
        compressed_data = gzip_data([
                                      { id: archived_point.id, raw_data: { lon: 14.0, lat: 53.0 } }
                                    ])
        allow(archive.file.blob).to receive(:download).and_return(compressed_data)
      end

      it 'fetches raw_data from archive' do
        result = archived_point.raw_data_with_archive
        expect(result).to eq({ 'id' => archived_point.id, 'raw_data' => { 'lon' => 14.0, 'lat' => 53.0 } }['raw_data'])
      end
    end

    context 'when raw_data is archived in an encrypted archive' do
      let(:archive) { create(:points_raw_data_archive, :encrypted, user: user) }
      let(:archived_point) do
        create(:point, user: user, raw_data: nil, raw_data_archived: true, raw_data_archive: archive)
      end

      before do
        encrypted_data = Points::RawData::Encryption.encrypt(
          gzip_data([{ id: archived_point.id, raw_data: { lon: 14.0, lat: 53.0 } }])
        )
        allow(archive.file.blob).to receive(:download).and_return(encrypted_data)
      end

      it 'decrypts and fetches raw_data from archive' do
        expect(archived_point.raw_data_with_archive).to eq({ 'lon' => 14.0, 'lat' => 53.0 })
      end
    end

    context 'when raw_data is archived but point not in archive' do
      let(:archive) { create(:points_raw_data_archive, user: user) }
      let(:archived_point) do
        create(:point, user: user, raw_data: nil, raw_data_archived: true, raw_data_archive: archive)
      end

      before do
        # Mock archive file with different point
        compressed_data = gzip_data([
                                      { id: 999, raw_data: { lon: 14.0, lat: 53.0 } }
                                    ])
        allow(archive.file.blob).to receive(:download).and_return(compressed_data)
      end

      it 'returns empty hash' do
        expect(archived_point.raw_data_with_archive).to eq({})
      end
    end
  end

  describe '#restore_raw_data!' do
    let(:archive) { create(:points_raw_data_archive, user: user) }
    let(:archived_point) do
      create(:point, user: user, raw_data: nil, raw_data_archived: true, raw_data_archive: archive)
    end

    it 'restores raw_data to database and clears archive flags' do
      new_data = { lon: 15.0, lat: 54.0 }
      archived_point.restore_raw_data!(new_data)

      archived_point.reload
      expect(archived_point.raw_data).to eq(new_data.stringify_keys)
      expect(archived_point.raw_data_archived).to be false
      expect(archived_point.raw_data_archive_id).to be_nil
    end
  end

  describe 'temporary cache' do
    let(:june_point) { create(:point, user: user, timestamp: Time.new(2024, 6, 15).to_i) }

    it 'checks temporary restore cache with correct key format' do
      cache_key = "raw_data:temp:#{user.id}:#{june_point.id}"
      cached_data = { lon: 16.0, lat: 55.0 }

      Rails.cache.write(cache_key, cached_data, expires_in: 1.hour)

      result = june_point.send(:check_temporary_restore_cache)
      expect(result).to eq(cached_data)
    end

    it 'serves points via cache after restore_to_memory even when archive month label differs' do
      memory_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_store)

      july_point = create(
        :point,
        user: user,
        timestamp: Time.utc(2024, 7, 3).to_i,
        raw_data: nil,
        raw_data_archived: true
      )

      archive = create(:points_raw_data_archive, user: user, year: 2024, month: 6)
      july_point.update_column(:raw_data_archive_id, archive.id)
      allow(archive.file.blob).to receive(:download).and_return(
        gzip_data([{ id: july_point.id, raw_data: { lon: 17.0, lat: 56.0 } }])
      )
      allow(Points::RawDataArchive).to receive(:for_month).with(user.id, 2024, 6).and_return([archive])

      Points::RawData::Restorer.new.restore_to_memory(user.id, 2024, 6)

      expect(july_point.raw_data_with_archive).to eq({ 'lon' => 17.0, 'lat' => 56.0 })
    end
  end

  describe '.archival_safe_upsert_all' do
    let(:base_row) do
      {
        lonlat: 'POINT(13.4 52.5)',
        timestamp: 1_700_000_000,
        user_id: user.id,
        raw_data: { 'src' => 'original' }
      }
    end

    let!(:archived_point) do
      create(:point, user: user,
                     lonlat: 'POINT(13.4 52.5)',
                     timestamp: 1_700_000_000,
                     raw_data: { 'src' => 'original' },
                     raw_data_archived: true,
                     raw_data_archive_id: create(:points_raw_data_archive, user: user).id)
    end

    it 'resets archival flags when a duplicate arrives with different raw_data' do
      Point.archival_safe_upsert_all(
        [base_row.merge(raw_data: { 'src' => 'reimport' })],
        returning: Arel.sql('id, xmax')
      )

      archived_point.reload
      expect(archived_point.raw_data).to eq({ 'src' => 'reimport' })
      expect(archived_point.raw_data_archived).to be false
      expect(archived_point.raw_data_archive_id).to be_nil
    end

    it 'keeps archival flags when a duplicate carries identical raw_data' do
      Point.archival_safe_upsert_all([base_row], returning: Arel.sql('id, xmax'))

      archived_point.reload
      expect(archived_point.raw_data_archived).to be true
      expect(archived_point.raw_data_archive_id).to be_present
    end

    it 'is a no-op for an empty batch' do
      expect(Point.archival_safe_upsert_all([], returning: Arel.sql('id'))).to eq([])
    end

    it 'inserts new points with default archival flags' do
      result = Point.archival_safe_upsert_all(
        [base_row.merge(timestamp: 1_700_000_060)],
        returning: Arel.sql('id, xmax')
      )

      point = Point.find(result.first['id'])
      expect(point.raw_data_archived).to be false
      expect(point.raw_data).to eq({ 'src' => 'original' })
    end

    it 'upserts rows in a deterministic order regardless of input order' do
      captured = nil
      allow(Point).to receive(:upsert_all) do |rows, **|
        captured = rows
        []
      end

      later = base_row.merge(timestamp: 1_700_000_300)
      earlier = base_row.merge(timestamp: 1_700_000_240)
      Point.archival_safe_upsert_all([later, earlier], returning: Arel.sql('id'))

      expect(captured).to eq([earlier, later])
    end

    it 'orders rows chronologically regardless of timestamp type or UTC offset' do
      captured = nil
      allow(Point).to receive(:upsert_all) do |rows, **|
        captured = rows
        []
      end

      later = base_row.merge(timestamp: DateTime.parse('2026-07-18T09:30:00+01:00'))
      earlier = base_row.merge(timestamp: DateTime.parse('2026-07-18T10:00:00+03:00'))
      Point.archival_safe_upsert_all([later, earlier], returning: Arel.sql('id'))

      expect(captured).to eq([earlier, later])
    end

    it 'orders rows by geographic coordinate rather than lexical WKT string' do
      captured = nil
      allow(Point).to receive(:upsert_all) do |rows, **|
        captured = rows
        []
      end

      east = base_row.merge(lonlat: 'POINT(13 52)', timestamp: 1_700_000_400)
      west = base_row.merge(lonlat: 'POINT(9 52)', timestamp: 1_700_000_460)
      Point.archival_safe_upsert_all([east, west], returning: Arel.sql('id'))

      expect(captured).to eq([west, east])
    end

    it 'does not raise while sorting a batch containing a malformed lonlat' do
      captured = nil
      allow(Point).to receive(:upsert_all) do |rows, **|
        captured = rows
        []
      end

      valid = base_row.merge(timestamp: 1_700_000_600)
      malformed = base_row.merge(lonlat: 'not-a-point', timestamp: 1_700_000_660)

      expect do
        Point.archival_safe_upsert_all([malformed, valid], returning: Arel.sql('id'))
      end.not_to raise_error
      expect(captured.first).to eq(valid)
    end

    context 'when the upsert hits a transient deadlock' do
      it 'retries with jittered backoff and returns the result' do
        attempts = 0
        allow(Point).to receive(:upsert_all).and_wrap_original do |original, *args, **kwargs|
          attempts += 1
          raise ActiveRecord::Deadlocked, 'deadlock detected' if attempts == 1

          original.call(*args, **kwargs)
        end
        allow(Point).to receive(:sleep)

        result = Point.archival_safe_upsert_all(
          [base_row.merge(timestamp: 1_700_000_120)],
          returning: Arel.sql('id, xmax')
        )

        expect(attempts).to eq(2)
        expect(Point.exists?(result.first['id'])).to be true
        expect(Point).to have_received(:sleep).with(be_between(0.1, 0.15)).once
      end

      it 'raises after exhausting retries' do
        allow(Point).to receive(:upsert_all).and_raise(ActiveRecord::Deadlocked, 'deadlock detected')
        allow(Point).to receive(:sleep)

        expect do
          Point.archival_safe_upsert_all(
            [base_row.merge(timestamp: 1_700_000_180)],
            returning: Arel.sql('id, xmax')
          )
        end.to raise_error(ActiveRecord::Deadlocked)

        expect(Point).to have_received(:sleep).exactly(3).times
      end
    end

    context 'when the upsert is canceled by a transient statement or lock timeout' do
      [ActiveRecord::QueryCanceled, ActiveRecord::LockWaitTimeout].each do |error_class|
        it "retries #{error_class} and returns the result" do
          attempts = 0
          allow(Point).to receive(:upsert_all).and_wrap_original do |original, *args, **kwargs|
            attempts += 1
            raise error_class, 'canceling statement' if attempts == 1

            original.call(*args, **kwargs)
          end
          allow(Point).to receive(:sleep)

          result = Point.archival_safe_upsert_all(
            [base_row.merge(timestamp: 1_700_000_240)],
            returning: Arel.sql('id, xmax')
          )

          expect(attempts).to eq(2)
          expect(Point.exists?(result.first['id'])).to be true
        end

        it "raises #{error_class} after exhausting retries" do
          allow(Point).to receive(:upsert_all).and_raise(error_class, 'canceling statement')
          allow(Point).to receive(:sleep)

          expect do
            Point.archival_safe_upsert_all(
              [base_row.merge(timestamp: 1_700_000_300)],
              returning: Arel.sql('id, xmax')
            )
          end.to raise_error(error_class)

          expect(Point).to have_received(:sleep).exactly(3).times
        end
      end
    end
  end

  describe 'raw_data mutation guard' do
    let(:archive) { create(:points_raw_data_archive, user: user) }
    let(:archived_point) do
      create(:point, user: user, raw_data: { 'old' => true }, raw_data_archived: true, raw_data_archive: archive)
    end

    it 'resets archival flags when raw_data changes on an archived point' do
      archived_point.update!(raw_data: { 'new' => true })

      archived_point.reload
      expect(archived_point.raw_data_archived).to be false
      expect(archived_point.raw_data_archive_id).to be_nil
    end

    it 'keeps archival flags when raw_data does not change' do
      archived_point.update!(altitude: 42)

      archived_point.reload
      expect(archived_point.raw_data_archived).to be true
      expect(archived_point.raw_data_archive_id).to eq(archive.id)
    end
  end

  def gzip_data(points_array)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    points_array.each do |point_data|
      gz.puts(point_data.to_json)
    end
    gz.close
    io.string
  end
end
