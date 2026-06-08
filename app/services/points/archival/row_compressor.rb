# frozen_string_literal: true

module Points
  module Archival
    class RowCompressor
      def initialize(points_relation)
        @points = points_relation
      end

      def compress
        io = StringIO.new
        gz = Zlib::GzipWriter.new(io)
        count = 0
        uncompressed_size = 0

        @points.order(:id).find_each(batch_size: 1000) do |point|
          line = Serializer.dump(point)
          uncompressed_size += line.bytesize
          gz.write(line)
          count += 1
        end

        gz.close
        { data: io.string.force_encoding(Encoding::ASCII_8BIT), count:, uncompressed_size: }
      end
    end
  end
end
