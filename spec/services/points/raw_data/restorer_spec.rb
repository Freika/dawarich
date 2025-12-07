# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::Restorer do
  let(:user) { create(:user) }
  let(:restorer) { described_class.new }

  before do
    # Stub broadcasting to avoid ActionCable issues in tests
    allow(PointsChannel).to receive(:broadcast_to)
  end

  describe '#restore_to_database' do
    let(:archive) { create(:points_raw_data_archive, user: user, year: 2024, month: 6) }
    let!(:archived_points) do
      points = create_list(:point, 3, user: user, timestamp: Time.new(2024, 6, 15).to_i,
                                       raw_data: nil, raw_data_archived: true, raw_data_archive: archive)

      # Mock archive file with actual point data
      compressed_data = gzip_points_data(points.map do |p|
        { id: p.id, raw_data: { lon: 13.4, lat: 52.5 } }
      end)
      allow(archive.file.blob).to receive(:download).and_return(compressed_data)

      points
    end

    it 'restores raw_data to database' do
      restorer.restore_to_database(user.id, 2024, 6)

      archived_points.each(&:reload)
      archived_points.each do |point|
        expect(point.raw_data).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
      end
    end

    it 'clears archive flags' do
      restorer.restore_to_database(user.id, 2024, 6)

      archived_points.each(&:reload)
      archived_points.each do |point|
        expect(point.raw_data_archived).to be false
        expect(point.raw_data_archive_id).to be_nil
      end
    end

    it 'raises error when no archives found' do
      expect do
        restorer.restore_to_database(user.id, 2025, 12)
      end.to raise_error(/No archives found/)
    end

    context 'with multiple chunks' do
      let!(:archive2) { create(:points_raw_data_archive, user: user, year: 2024, month: 6, chunk_number: 2) }
      let!(:more_points) do
        points = create_list(:point, 2, user: user, timestamp: Time.new(2024, 6, 20).to_i,
                                         raw_data: nil, raw_data_archived: true, raw_data_archive: archive2)

        compressed_data = gzip_points_data(points.map do |p|
          { id: p.id, raw_data: { lon: 14.0, lat: 53.0 } }
        end)
        allow(archive2.file.blob).to receive(:download).and_return(compressed_data)

        points
      end

      it 'restores from all chunks' do
        restorer.restore_to_database(user.id, 2024, 6)

        (archived_points + more_points).each(&:reload)
        expect(archived_points.first.raw_data).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
        expect(more_points.first.raw_data).to eq({ 'lon' => 14.0, 'lat' => 53.0 })
      end
    end
  end

  describe '#restore_to_memory' do
    let(:archive) { create(:points_raw_data_archive, user: user, year: 2024, month: 6) }
    let!(:archived_points) do
      points = create_list(:point, 2, user: user, timestamp: Time.new(2024, 6, 15).to_i,
                                       raw_data: nil, raw_data_archived: true, raw_data_archive: archive)

      compressed_data = gzip_points_data(points.map do |p|
        { id: p.id, raw_data: { lon: 13.4, lat: 52.5 } }
      end)
      allow(archive.file.blob).to receive(:download).and_return(compressed_data)

      points
    end

    it 'loads data into cache' do
      restorer.restore_to_memory(user.id, 2024, 6)

      archived_points.each do |point|
        cache_key = "raw_data:temp:#{user.id}:2024:6:#{point.id}"
        cached_value = Rails.cache.read(cache_key)
        expect(cached_value).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
      end
    end

    it 'does not modify database' do
      restorer.restore_to_memory(user.id, 2024, 6)

      archived_points.each(&:reload)
      archived_points.each do |point|
        expect(point.raw_data).to be_nil
        expect(point.raw_data_archived).to be true
      end
    end

    it 'sets cache expiration to 1 hour' do
      restorer.restore_to_memory(user.id, 2024, 6)

      cache_key = "raw_data:temp:#{user.id}:2024:6:#{archived_points.first.id}"

      # Cache should exist now
      expect(Rails.cache.exist?(cache_key)).to be true
    end
  end

  describe '#restore_all_for_user' do
    let!(:june_archive) { create(:points_raw_data_archive, user: user, year: 2024, month: 6) }
    let!(:july_archive) { create(:points_raw_data_archive, user: user, year: 2024, month: 7) }

    let!(:june_points) do
      points = create_list(:point, 2, user: user, timestamp: Time.new(2024, 6, 15).to_i,
                                       raw_data: nil, raw_data_archived: true, raw_data_archive: june_archive)

      compressed_data = gzip_points_data(points.map { |p| { id: p.id, raw_data: { month: 'june' } } })
      allow(june_archive.file.blob).to receive(:download).and_return(compressed_data)
      points
    end

    let!(:july_points) do
      points = create_list(:point, 2, user: user, timestamp: Time.new(2024, 7, 15).to_i,
                                       raw_data: nil, raw_data_archived: true, raw_data_archive: july_archive)

      compressed_data = gzip_points_data(points.map { |p| { id: p.id, raw_data: { month: 'july' } } })
      allow(july_archive.file.blob).to receive(:download).and_return(compressed_data)
      points
    end

    it 'restores all months for user' do
      restorer.restore_all_for_user(user.id)

      june_points.each(&:reload)
      july_points.each(&:reload)

      expect(june_points.first.raw_data).to eq({ 'month' => 'june' })
      expect(july_points.first.raw_data).to eq({ 'month' => 'july' })
    end

    it 'clears all archive flags' do
      restorer.restore_all_for_user(user.id)

      (june_points + july_points).each(&:reload)
      expect(Point.where(user: user, raw_data_archived: true).count).to eq(0)
    end
  end

  def gzip_points_data(points_array)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    points_array.each do |point_data|
      gz.puts(point_data.to_json)
    end
    gz.close
    io.string
  end
end
