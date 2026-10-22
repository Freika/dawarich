# frozen_string_literal: true

class MapEdits::Serializer
  def self.call(result)
    track_feature = if result.track
                      Tracks::GeojsonSerializer.new(result.track, include_segments: true).call[:features].first
                    end

    {
      point: Api::PointSerializer.new(result.point).call,
      track: track_feature,
      revision: {
        point: result.point_revision,
        track: result.track_revision
      },
      visited_countries: result.visited_countries
    }
  end
end
