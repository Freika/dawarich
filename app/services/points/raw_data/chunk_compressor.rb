# frozen_string_literal: true

module Points
  module RawData
    class ChunkCompressor
      def initialize(points_relation)
        @points = points_relation
      end

      def compress
        io = StringIO.new
        gz = Zlib::GzipWriter.new(io)
        written_count = 0
        uncompressed_size = 0

        @points.select(:id, :raw_data).find_each(batch_size: 1000) do |point|
          # Write as JSONL (one JSON object per line)
          json = { id: point.id, raw_data: point.raw_data }.to_json
          line = "#{json}\n"
          uncompressed_size += line.bytesize
          gz.write(line)
          written_count += 1
        end

        gz.close
        compressed_data = io.string.force_encoding(Encoding::ASCII_8BIT)

        { data: compressed_data, count: written_count, uncompressed_size: uncompressed_size }
      end
    end
  end
end
