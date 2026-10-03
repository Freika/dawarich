defmodule Dawarich.VisitsApi.Payload do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo}

  @joins "FROM visits v LEFT JOIN places p ON p.id=v.place_id LEFT JOIN areas a ON a.id=v.area_id"
  @keys ~w(id area_id user_id started_at ended_at duration name status confidence confidence_band)

  def count(where, args) do
    [[count]] = Repo.query!("SELECT COUNT(*) #{@joins} WHERE #{where}", args).rows
    count
  end

  def rows(where, args, tail) do
    Repo.query!(
      "SELECT v.id,v.area_id,v.user_id,#{RailsTime.sql("v.started_at", 3)},#{RailsTime.sql("v.ended_at", 3)}," <>
        "v.duration,v.name,CASE v.status WHEN 0 THEN 'suggested' WHEN 1 THEN 'confirmed' WHEN 2 THEN 'declined' END," <>
        "v.confidence,CASE WHEN v.confidence>=70 THEN 'high' WHEN v.confidence>=40 THEN 'medium' WHEN v.confidence IS NOT NULL THEN 'low' END," <>
        "CASE WHEN p.id IS NOT NULL THEN COALESCE(ST_Y(p.lonlat::geometry),p.latitude::double precision) ELSE a.latitude END," <>
        "CASE WHEN p.id IS NOT NULL THEN COALESCE(ST_X(p.lonlat::geometry),p.longitude::double precision) ELSE a.longitude END,p.id " <>
        "#{@joins} WHERE #{where}#{tail}",
      args
    ).rows
  end

  def term(row) do
    [lat, lon, id] = Enum.drop(row, 10)

    {:object,
     Enum.zip(@keys, row) ++
       [{"place", {:object, [{"latitude", lat}, {"longitude", lon}, {"id", id}]}}]}
  end
end
