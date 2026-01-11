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

        @points.select(:id, :raw_data).find_each(batch_size: 1000) do |point|
          # Write as JSONL (one JSON object per line)
          gz.puts({ id: point.id, raw_data: point.raw_data }.to_json)
          written_count += 1
        end

        gz.close
        compressed_data = io.string.force_encoding(Encoding::ASCII_8BIT)

        { data: compressed_data, count: written_count }
      end
    end
  end
end
