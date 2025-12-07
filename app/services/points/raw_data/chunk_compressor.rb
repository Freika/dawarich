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

        # Stream points to avoid memory issues with large months
        @points.select(:id, :raw_data).find_each(batch_size: 1000) do |point|
          # Write as JSONL (one JSON object per line)
          gz.puts({ id: point.id, raw_data: point.raw_data }.to_json)
        end

        gz.close
        io.string.force_encoding(Encoding::ASCII_8BIT)  # Returns compressed bytes in binary encoding
      end
    end
  end
end
