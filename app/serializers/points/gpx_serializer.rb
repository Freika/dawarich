# frozen_string_literal: true

# Simple wrapper class that acts like GPX::GPXFile but preserves enhanced XML
class EnhancedGpxFile < GPX::GPXFile
  def initialize(name, xml_string)
    super(name: name)
    @enhanced_xml = xml_string
  end

  def to_s
    @enhanced_xml
  end
end

class Points::GpxSerializer
  def initialize(points, name)
    @points = points
    @name = name
  end

  def call
    gpx_file = create_base_gpx_file
    add_track_points_to_gpx(gpx_file)
    xml_string = enhance_gpx_with_speed_and_course(gpx_file.to_s)

    EnhancedGpxFile.new("dawarich_#{name}", xml_string)
  end

  private

  attr_reader :points, :name

  def create_base_gpx_file
    gpx_file = GPX::GPXFile.new(name: "dawarich_#{name}")
    track = GPX::Track.new(name: "dawarich_#{name}")
    gpx_file.tracks << track

    track_segment = GPX::Segment.new
    track.segments << track_segment

    gpx_file
  end

  def add_track_points_to_gpx(gpx_file)
    track_segment = gpx_file.tracks.first.segments.first

    points.each do |point|
      track_point = create_track_point(point)
      track_segment.points << track_point
    end
  end

  def create_track_point(point)
    track_point_attrs = build_track_point_attributes(point)
    GPX::TrackPoint.new(**track_point_attrs)
  end

  def build_track_point_attributes(point)
    {
      lat: point.lat,
      lon: point.lon,
      elevation: point.altitude.to_f,
      time: point.recorded_at
    }
  end

  def enhance_gpx_with_speed_and_course(gpx_xml)
    xml_string = add_gpx_namespace(gpx_xml)
    enhance_trackpoints_with_speed_and_course(xml_string)
  end

  def add_gpx_namespace(gpx_xml)
    gpx_xml.sub('<gpx', '<gpx xmlns="http://www.topografix.com/GPX/1/1"')
  end

  def enhance_trackpoints_with_speed_and_course(xml_string)
    trkpt_count = 0
    xml_string.gsub(/(<trkpt[^>]*>.*?<\/trkpt>)/m) do |trkpt_xml|
      point = points[trkpt_count]
      trkpt_count += 1
      enhance_single_trackpoint(trkpt_xml, point)
    end
  end

  def enhance_single_trackpoint(trkpt_xml, point)
    enhanced_trkpt = add_speed_to_trackpoint(trkpt_xml, point)
    add_course_to_trackpoint(enhanced_trkpt, point)
  end

  def add_speed_to_trackpoint(trkpt_xml, point)
    return trkpt_xml unless should_include_speed?(point)

    trkpt_xml.sub(/(<ele>[^<]*<\/ele>)/, "\\1\n        <speed>#{point.velocity.to_f}</speed>")
  end

  def add_course_to_trackpoint(trkpt_xml, point)
    return trkpt_xml unless should_include_course?(point)

    extensions_xml = "\n        <extensions>\n          <course>#{point.course.to_f}</course>\n        </extensions>"
    trkpt_xml.sub(/\n      <\/trkpt>/, "#{extensions_xml}\n      </trkpt>")
  end

  def should_include_speed?(point)
    point.velocity.present? && point.velocity.to_f > 0
  end

  def should_include_course?(point)
    point.course.present?
  end
end
