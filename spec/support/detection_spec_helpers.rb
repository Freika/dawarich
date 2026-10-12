# frozen_string_literal: true

# Bridges VisitScenarioGenerator output into the value structs the pure
# detection stages consume.
module DetectionSpecHelpers
  def as_detection_points(hashes)
    hashes.each_with_index.map do |p, i|
      Visits::Detection::CandidateLoader::Pt.new(i + 1, p[:lat], p[:lon], p[:timestamp], p[:accuracy]&.round)
    end
  end

  def as_detection_segments(hashes)
    hashes.map do |s|
      Visits::Detection::CandidateLoader::Seg.new(
        s[:mode], s[:confidence_score], s[:corrected], s[:start_ts], s[:end_ts]
      )
    end
  end
end

RSpec.configure do |config|
  config.include DetectionSpecHelpers
end
