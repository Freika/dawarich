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
      cache_key = "raw_data:temp:#{user.id}:2024:6:#{june_point.id}"
      cached_data = { lon: 16.0, lat: 55.0 }

      Rails.cache.write(cache_key, cached_data, expires_in: 1.hour)

      # Access through send since check_temporary_restore_cache is private
      result = june_point.send(:check_temporary_restore_cache)
      expect(result).to eq(cached_data)
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
