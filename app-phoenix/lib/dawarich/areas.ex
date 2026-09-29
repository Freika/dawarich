defmodule Dawarich.Areas do
  @moduledoc false

  alias Dawarich.RailsCommands

  @earth_radius_km 6371.0
  @candidates """
  SELECT v.id,
         CASE WHEN pl.id IS NOT NULL THEN COALESCE(ST_Y(pl.lonlat::geometry), pl.latitude::float8) END,
         CASE WHEN pl.id IS NOT NULL THEN COALESCE(ST_X(pl.lonlat::geometry), pl.longitude::float8) END
  FROM visits v
  LEFT JOIN places pl ON pl.id = v.place_id
  WHERE v.user_id = $1 AND v.area_id IS NULL AND v.deleted_at IS NULL AND v.status <> 2 AND v.id > $2
  ORDER BY v.id
  LIMIT $3
  """
  @centroids """
  SELECT visit_id, AVG(ST_Y(lonlat::geometry)), AVG(ST_X(lonlat::geometry))
  FROM points WHERE visit_id = ANY($1) GROUP BY visit_id
  """
  @label """
  UPDATE visits SET area_id = $1,
    name = CASE WHEN status = 0 AND detection_version IS NOT NULL AND $2::text IS NOT NULL THEN $2::text ELSE name END
  WHERE id = ANY($3) AND area_id IS NULL
  RETURNING started_at
  """

  def relabel(repo, area_id, opts \\ []) do
    case area(repo, area_id) do
      nil ->
        :missing

      area ->
        batches(
          repo,
          area,
          0,
          Keyword.get(opts, :batch, 500),
          Keyword.get(opts, :before_label, fn _ -> :ok end)
        )
    end
  end

  def distance_m({lat1, lon1}, {lat2, lon2}) do
    r = :math.pi() / 180
    p1 = lat1 * r
    l1 = lon1 * r
    p2 = lat2 * r
    l2 = lon2 * r

    a =
      :math.pow(:math.sin((p2 - p1) / 2), 2) +
        :math.cos(p1) * :math.pow(:math.sin((l2 - l1) / 2), 2) * :math.cos(p2)

    2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a)) * @earth_radius_km * 1000
  end

  defp area(repo, id) do
    case repo.query!(
           "SELECT a.id, a.user_id, a.name, a.latitude::float8, a.longitude::float8, a.radius FROM areas a JOIN users u ON u.id = a.user_id AND u.deleted_at IS NULL WHERE a.id = $1",
           [id],
           log: false
         ).rows do
      [[id, user_id, name, lat, lon, radius]] ->
        %{
          id: id,
          user_id: user_id,
          label: if(String.trim(name) == "", do: nil, else: name),
          center: {lat, lon},
          radius: radius
        }

      [] ->
        nil
    end
  end

  defp batches(repo, area, after_id, size, before_label) do
    rows = repo.query!(@candidates, [area.user_id, after_id, size], log: false).rows
    centers = centers(repo, rows)
    inside = for [id | _] <- rows, inside?(area, Map.get(centers, id)), do: id

    if inside != [],
      do:
        (
          before_label.(inside)
          label!(repo, area, inside)
        )

    if length(rows) == size,
      do: batches(repo, area, rows |> List.last() |> hd(), size, before_label),
      else: :ok
  end

  defp centers(repo, rows) do
    {placed, point_backed} = Enum.split_with(rows, fn [_id, lat, _lon] -> not is_nil(lat) end)
    placed = Map.new(placed, fn [id, lat, lon] -> {id, {lat, lon}} end)
    ids = Enum.map(point_backed, &hd/1)

    if ids == [],
      do: placed,
      else:
        repo.query!(@centroids, [ids], log: false).rows
        |> Enum.reduce(placed, fn [id, lat, lon], acc -> Map.put(acc, id, {lat, lon}) end)
  end

  defp inside?(_area, nil), do: false
  defp inside?(_area, {nil, _lon}), do: false
  defp inside?(_area, {lat, lon}) when lat == 0 and lon == 0, do: false
  defp inside?(area, center), do: distance_m(center, area.center) <= area.radius

  defp label!(repo, area, ids) do
    {:ok, :ok} =
      repo.transaction(fn ->
        case repo.query!(@label, [area.id, area.label, ids], log: false).rows do
          [] ->
            :ok

          started ->
            RailsCommands.insert!(repo, "visit_months_changed", %{
              "user_id" => area.user_id,
              "started_at" =>
                Enum.map(started, fn [time] ->
                  time |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
                end)
            })
        end
      end)
  end
end
