defmodule Dawarich.Visits.VisitRescore do
  @moduledoc false

  alias Dawarich.{Geo, RubyFloat}
  alias Dawarich.Visits.ConfidenceScorer

  @points_sql "SELECT id, accuracy, ST_Y(lonlat::geometry), ST_X(lonlat::geometry) FROM points " <>
                "WHERE visit_id = $1 ORDER BY id"

  def run(repo, visit, policy, points \\ nil)

  def run(repo, visit, policy, nil), do: run(repo, visit, policy, points(repo, visit.id))

  def run(_repo, _visit, _policy, []), do: :ok

  def run(repo, visit, policy, points) do
    center = center(repo, visit, points)

    result =
      ConfidenceScorer.score(%{
        duration_seconds: visit.ended_at - visit.started_at,
        point_count: length(points),
        accuracies: Enum.map(points, & &1.accuracy),
        radius_meters: radius(points, center),
        stay_radius_meters: policy.stay_radius_m,
        min_points: policy.min_points,
        place_match: place_match(visit)
      })

    repo.query!(
      "UPDATE visits SET confidence = $2, confidence_breakdown = $3 WHERE id = $1",
      [visit.id, result.score, Jason.OrderedObject.new(result.breakdown)],
      log: false
    )

    :ok
  end

  def points(repo, visit_id) do
    for [id, accuracy, lat, lon] <- repo.query!(@points_sql, [visit_id], log: false).rows,
        do: %{id: id, accuracy: accuracy, lat: lat, lon: lon}
  end

  def center(repo, visit, points) do
    with nil <- area_center(repo, visit.area_id),
         nil <- place_center(repo, visit.place_id),
         do: points_center(points)
  end

  defp points_center([]), do: {0, 0}

  defp points_center(points) do
    count = length(points) * 1.0

    {RubyFloat.sum(Enum.map(points, & &1.lat)) / count,
     RubyFloat.sum(Enum.map(points, & &1.lon)) / count}
  end

  defp area_center(_repo, nil), do: nil

  defp area_center(repo, id) do
    case repo.query!("SELECT latitude::float8, longitude::float8 FROM areas WHERE id = $1", [id],
           log: false
         ).rows do
      [[lat, lon]] -> {lat, lon}
      [] -> nil
    end
  end

  defp place_center(_repo, nil), do: nil

  defp place_center(repo, id) do
    case repo.query!(
           "SELECT COALESCE(ST_Y(lonlat::geometry), latitude::float8), " <>
             "COALESCE(ST_X(lonlat::geometry), longitude::float8) FROM places WHERE id = $1",
           [id],
           log: false
         ).rows do
      [[lat, lon]] -> {lat, lon}
      [] -> nil
    end
  end

  defp place_match(%{area_id: id}) when id != nil, do: :area
  defp place_match(%{place_id: id}) when id != nil, do: :place
  defp place_match(_visit), do: nil

  defp radius(points, center) do
    max = points |> Enum.map(&Geo.distance_m(center, {&1.lat, &1.lon})) |> Enum.max()
    if max >= 15, do: max, else: 15
  end
end
