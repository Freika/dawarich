# frozen_string_literal: true

class Imports::SourceDetector
  class UnknownSourceError < StandardError; end

  DETECTION_RULES = {
    google_semantic_history: {
      required_keys: ['timelineObjects'],
      nested_patterns: [
        ['timelineObjects', 0, 'activitySegment'],
        ['timelineObjects', 0, 'placeVisit']
      ]
    },
    google_records: {
      required_keys: ['locations'],
      nested_patterns: [
        ['locations', 0, 'latitudeE7'],
        ['locations', 0, 'longitudeE7']
      ]
    },
    google_phone_takeout: {
      alternative_patterns: [
        # Pattern 1: Object with semanticSegments
        {
          required_keys: ['semanticSegments'],
          nested_patterns: [['semanticSegments', 0, 'startTime']]
        },
        # Pattern 2: Object with rawSignals
        {
          required_keys: ['rawSignals']
        },
        # Pattern 3: Array format with visit/activity objects
        {
          structure: :array,
          nested_patterns: [
            [0, 'visit', 'topCandidate', 'placeLocation'],
            [0, 'activity']
          ]
        }
      ]
    },
    geojson: {
      required_keys: %w[type features],
      required_values: { 'type' => 'FeatureCollection' },
      nested_patterns: [
        ['features', 0, 'type'],
        ['features', 0, 'geometry'],
        ['features', 0, 'properties']
      ]
    },
    owntracks: {
      structure: :rec_file_lines,
      line_pattern: /"_type":"location"/
    }
  }.freeze

  def initialize(file_content, filename = nil, file_path = nil)
    @file_content = file_content
    @filename = filename
    @file_path = file_path
  end

  def self.new_from_file_header(file_path)
    filename = File.basename(file_path)

    # For detection, read only first 2KB to optimize performance
    header_content = File.open(file_path, 'rb') { |f| f.read(2048) }

    new(header_content, filename, file_path)
  end

  def detect_source
    return :gpx if gpx_file?
    return :kml if kml_file?
    return :owntracks if owntracks_file?

    json_data = parse_json
    return nil unless json_data

    DETECTION_RULES.each do |format, rules|
      next if format == :owntracks # Already handled above

      return format if matches_format?(json_data, rules)
    end

    nil
  end

  def detect_source!
    format = detect_source
    raise UnknownSourceError, 'Unable to detect file format' unless format

    format
  end

  private

  attr_reader :file_content, :filename, :file_path

  def gpx_file?
    return false unless filename

    # Must have .gpx extension AND contain GPX XML structure
    return false unless filename.downcase.end_with?('.gpx')

    # Check content for GPX structure
    content_to_check =
      if file_path && File.exist?(file_path)
        # Read first 1KB for GPX detection
        File.open(file_path, 'rb') { |f| f.read(1024) }
      else
        file_content
      end
    (
      content_to_check.strip.start_with?('<?xml') ||
      content_to_check.strip.start_with?('<gpx')
    ) && content_to_check.include?('<gpx')
  end

  def kml_file?
    return false unless filename&.downcase&.end_with?('.kml', '.kmz')

    content_to_check =
      if file_path && File.exist?(file_path)
        # Read first 1KB for KML detection
        File.open(file_path, 'rb') { |f| f.read(1024) }
      else
        file_content
      end

    # Check if it's a KMZ file (ZIP archive)
    if filename&.downcase&.end_with?('.kmz')
      # KMZ files are ZIP archives, check for ZIP signature
      # ZIP files start with "PK" (0x50 0x4B)
      return content_to_check[0..1] == 'PK'
    end

    # For KML files, check XML structure
    (
      content_to_check.strip.start_with?('<?xml') ||
      content_to_check.strip.start_with?('<kml')
    ) && content_to_check.include?('<kml')
  end

  def owntracks_file?
    return false unless filename

    # Check for .rec extension first (fastest check)
    return true if filename.downcase.end_with?('.rec')

    # Check for specific OwnTracks line format in content
    content_to_check = if file_path && File.exist?(file_path)
                         # For OwnTracks, read first few lines only
                         File.open(file_path, 'r') { |f| f.read(2048) }
                       else
                         file_content
                       end

    content_to_check.lines.any? { |line| line.include?('"_type":"location"') }
  end

  def parse_json
    # If we have a file path, use streaming for better memory efficiency
    if file_path && File.exist?(file_path)
      Oj.load_file(file_path, mode: :compat)
    else
      Oj.load(file_content, mode: :compat)
    end
  rescue Oj::ParseError, JSON::ParserError
    # If full file parsing fails but we have a file path, try with just the header
    if file_path && file_content.length < 2048
      begin
        File.open(file_path, 'rb') do |f|
          partial_content = f.read(4096) # Try a bit more content
          Oj.load(partial_content, mode: :compat)
        end
      rescue Oj::ParseError, JSON::ParserError
        nil
      end
    else
      nil
    end
  end

  def matches_format?(json_data, rules)
    # Handle alternative patterns (for google_phone_takeout)
    if rules[:alternative_patterns]
      return rules[:alternative_patterns].any? { |pattern| matches_pattern?(json_data, pattern) }
    end

    matches_pattern?(json_data, rules)
  end

  def matches_pattern?(json_data, pattern)
    # Check structure requirements
    return false unless structure_matches?(json_data, pattern[:structure])

    # Check required keys
    return false if pattern[:required_keys] && !has_required_keys?(json_data, pattern[:required_keys])

    # Check required values
    return false if pattern[:required_values] && !has_required_values?(json_data, pattern[:required_values])

    # Check nested patterns
    return false if pattern[:nested_patterns] && !has_nested_patterns?(json_data, pattern[:nested_patterns])

    true
  end

  def structure_matches?(json_data, required_structure)
    case required_structure
    when :array
      json_data.is_a?(Array)
    when nil
      true # No specific structure required
    else
      true # Default to no restriction
    end
  end

  def has_required_keys?(json_data, keys)
    return false unless json_data.is_a?(Hash)

    keys.all? { |key| json_data.key?(key) }
  end

  def has_required_values?(json_data, values)
    return false unless json_data.is_a?(Hash)

    values.all? { |key, expected_value| json_data[key] == expected_value }
  end

  def has_nested_patterns?(json_data, patterns)
    patterns.any? { |pattern| nested_key_exists?(json_data, pattern) }
  end

  def nested_key_exists?(data, key_path)
    current = data

    key_path.each do |key|
      return false unless current

      if current.is_a?(Array)
        return false if key >= current.length

        current = current[key]
      elsif current.is_a?(Hash)
        return false unless current.key?(key)

        current = current[key]
      else
        return false
      end
    end

    !current.nil?
  end
end
