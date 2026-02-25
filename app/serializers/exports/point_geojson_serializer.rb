# frozen_string_literal: true

class Exports::PointGeojsonSerializer
  BATCH_SIZE = 1000

  def initialize(points_scope)
    @points_scope = points_scope
  end

  def call
    tempfile = Tempfile.new(['export', '.json'])
    tempfile.binmode

    write_to(tempfile)

    tempfile.rewind
    tempfile
  end

  private

  attr_reader :points_scope

  def write_to(io)
    io.write('{"type":"FeatureCollection","features":[')

    first = true
    points_scope.in_batches(of: BATCH_SIZE, order: :asc) do |batch|
      batch.order(:timestamp).each do |point|
        io.write(',') unless first
        first = false

        feature = {
          type: 'Feature',
          geometry: {
            type: 'Point',
            coordinates: [point.lon, point.lat]
          },
          properties: PointSerializer.new(point).call
        }

        io.write(Oj.dump(feature, mode: :compat))
      end
    end

    io.write(']}')
  end
end
