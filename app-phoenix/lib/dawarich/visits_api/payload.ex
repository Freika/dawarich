defmodule Dawarich.VisitsApi.Payload do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo}

  @joins "FROM visits v LEFT JOIN places p ON p.id=v.place_id LEFT JOIN areas a ON a.id=v.area_id"
  @keys ~w(id area_id user_id started_at ended_at duration name status confidence confidence_band)

  def count(where, args, repo \\ Repo) do
    [[count]] = repo.query!("SELECT COUNT(*) #{@joins} WHERE #{where}", args).rows
    count
  end

  def rows(where, args, tail, repo \\ Repo) do
    repo.query!(
      "SELECT v.id,v.area_id,v.user_id,#{RailsTime.sql("v.started_at", 3)},#{RailsTime.sql("v.ended_at", 3)}," <>
        "v.duration,v.name,CASE v.status WHEN 0 THEN 'suggested' WHEN 1 THEN 'confirmed' WHEN 2 THEN 'declined' END," <>
        "v.confidence,CASE WHEN v.confidence>=70 THEN 'high' WHEN v.confidence>=40 THEN 'medium' WHEN v.confidence IS NOT NULL THEN 'low' END," <>
        "CASE WHEN p.id IS NOT NULL THEN to_json(COALESCE(ST_Y(p.lonlat::geometry),p.latitude::double precision)) ELSE #{decimal("a.latitude")} END," <>
        "CASE WHEN p.id IS NOT NULL THEN to_json(COALESCE(ST_X(p.lonlat::geometry),p.longitude::double precision)) ELSE #{decimal("a.longitude")} END,p.id " <>
        "#{@joins} WHERE #{where}#{tail}",
      args
    ).rows
  end

  def term(row) do
    [lat, lon, id] = Enum.drop(row, 10)
    lat = if id && is_number(lat), do: lat * 1.0, else: lat
    lon = if id && is_number(lon), do: lon * 1.0, else: lon

    {:object,
     Enum.zip(@keys, row) ++
       [{"place", {:object, [{"latitude", lat}, {"longitude", lon}, {"id", id}]}}]}
  end

  defp decimal(column),
    do:
      "to_json(trim_scale(#{column})::text || CASE WHEN scale(trim_scale(#{column}))=0 THEN '.0' ELSE '' END)"
end
