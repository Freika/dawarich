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
    it 'returns compressed gzip data' do
      result = compressor.compress
      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'compresses points as JSONL format' do
      compressed = compressor.compress

      # Decompress and verify format
      io = StringIO.new(compressed)
      gz = Zlib::GzipReader.new(io)
      lines = gz.readlines
      gz.close

      expect(lines.count).to eq(3)

      # Each line should be valid JSON
      lines.each_with_index do |line, index|
        data = JSON.parse(line)
        expect(data).to have_key('id')
        expect(data).to have_key('raw_data')
        expect(data['id']).to eq(points[index].id)
      end
    end

    it 'includes point ID and raw_data in each line' do
      compressed = compressor.compress

      io = StringIO.new(compressed)
      gz = Zlib::GzipReader.new(io)
      first_line = gz.readline
      gz.close

      data = JSON.parse(first_line)
      expect(data['id']).to eq(points.first.id)
      expect(data['raw_data']).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
    end

    it 'processes points in batches' do
      # Create many points to test batch processing
      many_points = create_list(:point, 2500, user: user, raw_data: { lon: 13.4, lat: 52.5 })
      large_compressor = described_class.new(Point.where(id: many_points.map(&:id)))

      compressed = large_compressor.compress

      io = StringIO.new(compressed)
      gz = Zlib::GzipReader.new(io)
      line_count = 0
      gz.each_line { line_count += 1 }
      gz.close

      expect(line_count).to eq(2500)
    end

    it 'produces smaller compressed output than uncompressed' do
      compressed = compressor.compress

      # Decompress to get original size
      io = StringIO.new(compressed)
      gz = Zlib::GzipReader.new(io)
      decompressed = gz.read
      gz.close

      # Compressed should be smaller
      expect(compressed.bytesize).to be < decompressed.bytesize
    end
  end
end
