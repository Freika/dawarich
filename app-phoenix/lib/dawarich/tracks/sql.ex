defmodule Dawarich.Tracks.Sql do
  @moduledoc false

  def device_raw, do: "CASE WHEN p.source_id IS NULL THEN p.tracker_id ELSE ps.tracker_id END"
  def device, do: "COALESCE(#{device_raw()}, '')"
  def device_join, do: "LEFT JOIN point_sources ps ON ps.id = p.source_id"
  def altitude, do: "COALESCE(p.altitude_decimal, p.altitude::numeric)"

  def not_held_by_extraction,
    do:
      "NOT EXISTS (SELECT 1 FROM imports i WHERE i.id = p.import_id AND " <>
        "(i.additional_data_extraction_status IN (1, 2) OR " <>
        "(i.status = 1 AND i.additional_data_extraction_status = 0 AND i.source IN (0, 3, 4, 13))))"

  def outranking(segment),
    do:
      "(#{segment}.corrected_at IS NOT NULL OR " <>
        "COALESCE(#{segment}.source IN ('google_phone_takeout', 'google_semantic_history', 'polarsteps'), false))"

  def kept(track),
    do:
      "(#{track}.import_id IS NOT NULL OR EXISTS (SELECT 1 FROM track_segments s WHERE s.track_id = #{track}.id AND #{outranking("s")}))"
end
