# frozen_string_literal: true

class Exports::PointGpxSerializer
  BATCH_SIZE = 1000

  def initialize(points_scope, name)
    @points_scope = points_scope
    @name = name
  end

  def call
    tempfile = Tempfile.new(['export', '.gpx'])
    tempfile.binmode

    write_to(tempfile)

    tempfile.rewind
    tempfile
  end

  private

  attr_reader :points_scope, :name

  def write_to(io)
    write_header(io)

    points_scope.in_batches(of: BATCH_SIZE, order: :asc) do |batch|
      batch.order(:timestamp).each do |point|
        write_trackpoint(io, point)
      end
    end

    write_footer(io)
  end

  def write_header(io)
    io.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="Dawarich">
        <trk>
          <name>dawarich_#{escape_xml(name)}</name>
          <trkseg>
    XML
  end

  def write_footer(io)
    io.write(<<~XML)
          </trkseg>
        </trk>
      </gpx>
    XML
  end

  def write_trackpoint(io, point)
    io.write("      <trkpt lat=\"#{point.lat}\" lon=\"#{point.lon}\">\n")
    io.write("        <ele>#{point.altitude.to_f}</ele>\n")

    if point.velocity.present? && point.velocity.to_f > 0
      io.write("        <speed>#{point.velocity.to_f}</speed>\n")
    end

    io.write("        <time>#{point.recorded_at.xmlschema}</time>\n")

    if point.course.present?
      io.write("        <extensions>\n")
      io.write("          <course>#{point.course.to_f}</course>\n")
      io.write("        </extensions>\n")
    end

    io.write("      </trkpt>\n")
  end

  def escape_xml(str)
    str.to_s.encode(xml: :text)
  end
end
