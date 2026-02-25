# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::ChunkCompressor do
  let(:user) { create(:user) }

  before do
    # Stub broadcasting to avoid ActionCable issues in tests
    allow(PointsChannel).to receive(:broadcast_to)
  end
  let(:points) do
    [
      create(:point, user: user, raw_data: { lon: 13.4, lat: 52.5 }),
      create(:point, user: user, raw_data: { lon: 13.5, lat: 52.6 }),
      create(:point, user: user, raw_data: { lon: 13.6, lat: 52.7 })
    ]
  end
  let(:compressor) { described_class.new(Point.where(id: points.map(&:id))) }

  describe '#compress' do
    it 'returns a hash with data and count' do
      result = compressor.compress

      expect(result).to be_a(Hash)
      expect(result).to have_key(:data)
      expect(result).to have_key(:count)
      expect(result[:data]).to be_a(String)
      expect(result[:data].encoding.name).to eq('ASCII-8BIT')
      expect(result[:count]).to eq(3)
    end

    it 'returns correct count of compressed points' do
      result = compressor.compress

      expect(result[:count]).to eq(points.count)
    end

    it 'compresses points as JSONL format' do
      result = compressor.compress
      compressed = result[:data]

      # Decompress and verify format
      io = StringIO.new(compressed)
      gz = Zlib::GzipReader.new(io)
      lines = gz.readlines
      gz.close

      expect(lines.count).to eq(3)
      expect(result[:count]).to eq(3)

      # Each line should be valid JSON
      lines.each_with_index do |line, index|
        data = JSON.parse(line)
        expect(data).to have_key('id')
        expect(data).to have_key('raw_data')
        expect(data['id']).to eq(points[index].id)
      end
    end

    it 'includes point ID and raw_data in each line' do
      result = compressor.compress
      compressed = result[:data]

      io = StringIO.new(compressed)
      gz = Zlib::GzipReader.new(io)
      first_line = gz.readline
      gz.close

      data = JSON.parse(first_line)
      expect(data['id']).to eq(points.first.id)
      expect(data['raw_data']).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
    end

    it 'processes points in batches and returns correct count' do
      # Create many points to test batch processing with unique timestamps
      many_points = []
      base_time = Time.new(2024, 6, 15).to_i
      2500.times do |i|
        many_points << create(:point, user: user, timestamp: base_time + i, raw_data: { lon: 13.4, lat: 52.5 })
      end
      large_compressor = described_class.new(Point.where(id: many_points.map(&:id)))

      result = large_compressor.compress
      compressed = result[:data]

      io = StringIO.new(compressed)
      gz = Zlib::GzipReader.new(io)
      line_count = 0
      gz.each_line { line_count += 1 }
      gz.close

      expect(line_count).to eq(2500)
      expect(result[:count]).to eq(2500)
    end

    it 'returns uncompressed_size matching the actual JSONL byte size' do
      result = compressor.compress

      io = StringIO.new(result[:data])
      gz = Zlib::GzipReader.new(io)
      decompressed = gz.read
      gz.close

      expect(result[:uncompressed_size]).to eq(decompressed.bytesize)
    end

    it 'produces smaller compressed output than uncompressed' do
      result = compressor.compress
      compressed = result[:data]

      # Decompress to get original size
      io = StringIO.new(compressed)
      gz = Zlib::GzipReader.new(io)
      decompressed = gz.read
      gz.close

      # Compressed should be smaller
      expect(compressed.bytesize).to be < decompressed.bytesize
    end

    context 'with empty point set' do
      let(:empty_compressor) { described_class.new(Point.none) }

      it 'returns zero count for empty point set' do
        result = empty_compressor.compress

        expect(result[:count]).to eq(0)
        expect(result[:data]).to be_a(String)
      end
    end
  end
end
