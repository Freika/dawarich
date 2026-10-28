# frozen_string_literal: true

module Exploration
  class FlightEvidence
    # Evaluate all supported modes, independently of the user's display preferences.
    # This is a private temporary result; exploration does not rewrite their tracks.
    def self.prepare!(user, from: nil, to: nil)
      connection = ApplicationRecord.connection
      connection.execute('DROP TABLE IF EXISTS pg_temp.exploration_modes')
      connection.execute(<<~SQL)
        CREATE TEMP TABLE exploration_modes(track_id bigint,start_ts bigint,end_ts bigint,
          flying boolean,manual boolean,include_end boolean) ON COMMIT DROP
      SQL
      tracks = user.tracks
      tracks = tracks.where('end_at >= ? AND start_at <= ?', from, to) if from && to
      tracks.find_each do |track|
        preserved = track.track_segments.manually_corrected.to_a
        auto = TransportationModes::Detector.new(track, enabled_modes: Track::TRANSPORTATION_MODES.keys,
                                                preserved: preserved, fallback: false).call
        # Detector anchors legacy corrections. Reload them to use those anchors.
        preserved = track.track_segments.manually_corrected.to_a
        rows = auto.select { |s| s[:mode].to_s == 'flying' }.map do |s|
          [track.id, s[:start_at].to_i, s[:end_at].to_i, true, false, s[:end_at] == track.end_at]
        end
        rows.concat(preserved.filter_map do |s|
          next unless s.start_at && s.end_at

          [track.id, s.start_at.to_i, s.end_at.to_i, s.flying?, true, true]
        end)
        next if rows.empty?

        values = rows.map { |r| "(#{r.map { |v| connection.quote(v) }.join(',')})" }.join(',')
        connection.execute("INSERT INTO exploration_modes VALUES #{values}")
      end
      connection.execute('CREATE INDEX ON exploration_modes(track_id,start_ts,end_ts)')
    end

    def self.qualifying(relation)
      relation.where(qualifying_sql)
    end

    def self.qualifying_sql
      <<~SQL.squish
        NOT EXISTS (
          SELECT 1 FROM exploration_modes f WHERE f.track_id=points.track_id AND f.flying
            AND points.timestamp >= f.start_ts
            AND (points.timestamp < f.end_ts OR (f.include_end AND points.timestamp=f.end_ts))
            AND (f.manual OR NOT EXISTS (
              SELECT 1 FROM exploration_modes m WHERE m.track_id=points.track_id AND m.manual
                AND NOT m.flying AND points.timestamp BETWEEN m.start_ts AND m.end_ts
            ))
        )
      SQL
    end
  end
end
