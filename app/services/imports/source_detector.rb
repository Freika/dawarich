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
        # Pattern 3: Array format with visit/activity/timelinePath objects
        {
          structure: :array,
          nested_patterns: [
            [0, 'visit', 'topCandidate', 'placeLocation'],
            [0, 'activity'],
            [0, 'timelinePath']
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
    polarsteps: {
      alternative_patterns: [
        {
          required_keys: ['locations'],
          nested_patterns: [
            ['locations', 0, 'lat'],
            ['locations', 0, 'lon'],
            ['locations', 0, 'time']
          ]
        },
        {
          structure: :array,
          nested_patterns: [
            [0, 'arrived'],
            [0, 'departed']
          ]
        }
      ]
    },
    owntracks: {
      structure: :rec_file_lines,
      line_pattern: /"_type":"location"/
    }
  }.freeze

  MAX_DETECTION_BYTES = 8192
  MAX_RAW_DETECTION_BYTES = 262_144

  UTF8_BOM = "\xEF\xBB\xBF".b.freeze
  PARSE_ERRORS = [Oj::ParseError, JSON::ParserError, EncodingError, ArgumentError].freeze

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
    return :zip if zip_file?
    return :fit if fit_file?
    return :tcx if tcx_file?
    return :csv if csv_file?

    json_data = parse_json

    if json_data
      DETECTION_RULES.each do |format, rules|
        next if format == :owntracks # Already handled above

        return format if matches_format?(json_data, rules)
      end
    end

    # Fallback: detect from raw content when JSON parsing fails (e.g. deeply nested truncation)
    detect_from_raw_content
  end

  def detect_source!
    format = detect_source
    return format if format

    raise UnknownSourceError, unsupported_reason
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
    return false if content_to_check.blank?

    content_to_check.lines.any? { |line| line.include?('"_type":"location"') }
  end

  def zip_file?
    return false unless filename&.downcase&.end_with?('.zip')

    bytes = file_content&.bytes
    bytes && bytes.length >= 4 && bytes[0..3] == [0x50, 0x4B, 0x03, 0x04]
  end

  def fit_file?
    return false unless filename&.downcase&.end_with?('.fit')

    bytes = file_content&.bytes
    bytes && bytes.length >= 12 && bytes[8..11] == [0x2E, 0x46, 0x49, 0x54]
  end

  def tcx_file?
    return false unless filename&.downcase&.end_with?('.tcx')

    file_content&.include?('<TrainingCenterDatabase')
  end

  def csv_file?
    return false unless filename&.downcase&.end_with?('.csv')

    first_line = file_content&.lines&.first&.strip
    return false if first_line.nil?

    headers = first_line.split(/[,;\t]/).map { |h| h.strip.delete(%(\"')).strip.downcase }
    all_aliases = Imports::FieldAliases::ALIASES.values.flatten.map(&:downcase)
    matched = headers.count { |h| all_aliases.include?(h) }
    matched >= 2
  end

  def detect_from_raw_content
    content = read_for_raw_detection
    return nil if content.blank?

    if content.include?('"semanticSegments"') &&
       (content.include?('"startTime"') || content.include?('"visit"') || content.include?('"activity"'))
      :google_phone_takeout
    elsif content.include?('"timelineObjects"') &&
          (content.include?('"activitySegment"') || content.include?('"placeVisit"'))
      :google_semantic_history
    elsif content.include?('"locations"') && content.include?('"latitudeE7"')
      :google_records
    elsif content.include?('"FeatureCollection"') && content.include?('"features"')
      :geojson
    elsif content.include?('"rawSignals"')
      :google_phone_takeout
    elsif content.include?('"timelinePath"') &&
          (content.include?('"startTime"') || content.include?('"endTime"'))
      :google_phone_takeout
    elsif content.include?('"topCandidate"') && content.include?('"placeLocation"')
      :google_phone_takeout
    elsif content.include?('"arrived"') && content.include?('"departed"') && content.include?('"segment-')
      :polarsteps
    end
  end

  def parse_json
    content = read_for_json_parse
    content = strip_bom(content)

    Oj.load(content, mode: :compat)
  rescue *PARSE_ERRORS
    # Partial read may produce incomplete JSON — try to detect from truncated
    # content by closing any open structures.
    attempt_partial_json_parse(content)
  end

  def attempt_partial_json_parse(content)
    return nil if content.blank?

    ["#{content}]", "#{content}}]", "#{content}}}]"].each do |patched|
      return Oj.load(patched, mode: :compat)
    rescue *PARSE_ERRORS
      next
    end

    nil
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

  def read_for_json_parse
    if file_path && File.exist?(file_path)
      File.open(file_path, 'rb') { |f| f.read(MAX_DETECTION_BYTES) }
    else
      file_content
    end
  end

  def read_for_raw_detection
    if file_path && File.exist?(file_path)
      File.open(file_path, 'rb') { |f| f.read(MAX_RAW_DETECTION_BYTES) }
    else
      file_content
    end
  end

  def strip_bom(content)
    return content if content.blank?
    return content unless content.bytesize >= 3 && content.byteslice(0, 3).b == UTF8_BOM

    content.byteslice(3, content.bytesize - 3)
  end

  def unsupported_reason
    content = read_for_raw_detection.to_s

    return 'The uploaded file is empty (0 bytes).' if content.empty?

    binary_reason = unsupported_binary_reason(content)
    return binary_reason if binary_reason

    stripped = content.strip
    return 'The uploaded file contains no data (empty JSON object or array).' if EMPTY_JSON_BODIES.include?(stripped)

    if content.include?('You have encrypted Timeline backups')
      'Your Google Timeline data is encrypted. Open the Google Maps app, ' \
        'turn off Timeline encryption in your settings, then re-export your data.'
    elsif content.lstrip.start_with?('<!DOCTYPE html', '<!doctype html', '<html', '<HTML')
      'This is an HTML page (likely "archive_browser.html" from your Google Takeout), ' \
        'not the data file. Open the Takeout archive and look for the .json or .kml inside.'
    elsif content.include?('"timelineEdits"')
      'Google Timeline Edits format is not yet supported. Please upload Records.json ' \
        'or the files inside the Timeline/ folder of your Google Takeout instead.'
    elsif content.include?('"deviceSettings"') ||
          (content.include?('"gaiaId"') && content.include?('"hasReportedLocations"'))
      'This file contains your Google Maps settings, not location data. ' \
        'Look for "Records.json" or files inside "Timeline/" in your Google Takeout.'
    elsif content.include?('"placeUrl"') && content.include?('"selectedChoice"')
      'This is a Google Maps place-feedback file (Maps Q&A answers like "Was this place open?"), ' \
        'not your location history. Look for "Records.json" or files inside "Timeline/" in your Google Takeout.'
    elsif google_my_activity?(content)
      'This is a Google "My Activity" log (search and Maps activity), not your location history. ' \
        'Look for "Records.json" or files inside "Timeline/" in your Google Takeout.'
    elsif google_saved_places?(content)
      'This is a Google saved-places / geocodes file, not your location history. ' \
        'Look for "Records.json" or files inside "Timeline/" in your Google Takeout.'
    elsif amazon_order?(content)
      'This is an Amazon order export, not location data. ' \
        'Dawarich imports location history from Google Takeout, OwnTracks, GPX, and similar sources.'
    elsif snapchat_export?(content)
      'This appears to be a Snapchat data export, not location data. ' \
        'Dawarich imports location history from Google Takeout, OwnTracks, GPX, and similar sources.'
    elsif looks_like_json_fragment?(content)
      'The uploaded file appears to be a truncated or corrupted fragment of a JSON file ' \
        '(it does not start with "{" or "["). Please re-export and upload the original complete file.'
    else
      'Unable to detect file format'
    end
  end

  EMPTY_JSON_BODIES = ['{}', '[]', '[ ]'].freeze

  def unsupported_binary_reason(content)
    return nil if content.bytesize < 4

    head4 = content.byteslice(0, 4)
    head8 = content.byteslice(0, 8)
    head_bytes = content.bytes

    if head4 == '%PDF'
      'PDF files are not supported. Open the PDF and find your actual location data file.'
    elsif head4.start_with?('Rar!')
      'RAR archives are not supported. Please extract the archive and upload the data files inside.'
    elsif head8 == 'bplist00'
      'Apple binary plist (.plist) files are not supported.'
    elsif head_bytes[0, 2] == [0x1F, 0x8B]
      'Gzip-compressed files (.gz) are not auto-decompressed. Please decompress the file and re-upload the contents.'
    elsif head_bytes[0, 8] == [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
      'Microsoft Office documents (Word/Excel) are not supported. Please upload your location data file.'
    elsif heic_file?(content)
      'HEIC image files are not supported. Photos do not contain a location history; ' \
        'connect your photo library via the Immich or PhotoPrism integration to import photo locations.'
    elsif head_bytes[0, 3] == [0xFF, 0xD8, 0xFF]
      'JPEG image files are not supported. Photos do not contain a location history; ' \
        'connect your photo library via the Immich or PhotoPrism integration to import photo locations.'
    elsif head8 == "\x89PNG\r\n\x1A\n".b
      'PNG image files are not supported. Please upload your location data file (.json, .gpx, .kml, etc).'
    elsif ds_store?(head_bytes)
      'This is a macOS Finder metadata file (.DS_Store), not a data file. Please upload your actual location export.'
    end
  end

  SNAPCHAT_MARKERS = [
    'Snap Privacy Policy',
    '"Snap Inc.',
    '"Selfies"',
    '"Friends"',
    '"Public Users"',
    '"Last Active Timezone"'
  ].freeze

  def snapchat_export?(content)
    return true if SNAPCHAT_MARKERS.any? { |m| content.include?(m) }

    content.include?('"Login History"') && content.include?('"Permissions"')
  end

  def google_my_activity?(content)
    content.include?('"header": "Maps"') ||
      content.include?('"header":"Maps"') ||
      (content.include?('"titleUrl"') && content.include?('"header"'))
  end

  def google_saved_places?(content)
    return true if content.include?('"geocodes"') && content.include?('"latE7"')
    return true if content.include?('"placeId":"ChIJ') || content.include?('"placeID": "ChIJ')

    content.include?('"displayName"') && content.include?('"formattedAddress"')
  end

  def amazon_order?(content)
    content.include?('"OrderNumber"') && content.include?('"EstimatedDeliveryDate"')
  end

  def looks_like_json_fragment?(content)
    return false if content.bytesize < 8

    stripped = content.strip
    return false if stripped.start_with?('{', '[')

    stripped.start_with?('"timestamp"', '"position"', '"latitude"', '"longitude"', '"_type"', '"lat"')
  end

  def heic_file?(content)
    return false if content.bytesize < 12

    box = content.byteslice(4, 8)
    %w[ftypheic ftypheix ftypmif1 ftypheis].include?(box)
  end

  def ds_store?(head_bytes)
    head_bytes[4, 4] == 'Bud1'.bytes
  end
end
