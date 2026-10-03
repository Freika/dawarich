defmodule Dawarich.VisitsApi.Read do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo}
  alias Dawarich.VisitsApi.Payload
  alias DawarichWeb.Api.Params
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @active "v.user_id=$1 AND v.deleted_at IS NULL AND v.status!=2"
  @bounds ~w(sw_lat sw_lng ne_lat ne_lng)
  @calendar_words ~w(jan january feb february mar march apr april may jun june jul july aug august sep sept september oct october nov november dec december mon monday tue tues tuesday wed wednesday thu thur thurs thursday fri friday sat saturday sun sunday am pm ut utc gmt est edt cst cdt mst mdt pst pdt cet cest eet eest wet west bst ist jst hst akst akdt nzst nzdt now today tomorrow yesterday)

  def index(owner, params, zone) do
    RailsTime.with_zone(zone, fn ->
      box? = params["selection"] == "true" and Enum.all?(@bounds, &Ruby.present?(params[&1]))

      with {:ok, from} <- time(params["start_at"], box?),
           {:ok, to} <- time(params["end_at"], box?),
           {:ok, where, args} <- area(params, box?, @active, [owner]),
           {where, args} = window(where, args, from, to),
           {:ok, tail, headers} <- page(params, where, args) do
        order = if box?, do: " DESC", else: " ASC"
        rows = Payload.rows(where, args, " ORDER BY v.started_at" <> order <> tail)
        {:ok, Enum.map(rows, &Payload.term/1), headers}
      end
    end)
  end

  def show(owner, id, zone, repo \\ Repo, active? \\ true) do
    RailsTime.with_zone(repo, zone, fn ->
      where = if active?, do: @active, else: "v.user_id=$1"

      case Payload.rows(where <> " AND v.id=$2", [owner, id], "", repo) do
        [row] -> {:ok, Payload.term(row)}
        [] -> :not_found
      end
    end)
  end

  def possible_places(owner, id, zone, repo \\ Dawarich.Jobs.repo()) do
    RailsTime.with_zone(repo, zone, fn ->
      with {:ok, visit} <- Dawarich.VisitsApi.Effects.load(repo, owner, id) do
        [[lat, lon]] =
          repo.query!(
            "SELECT CASE WHEN a.id IS NOT NULL THEN a.latitude WHEN p.id IS NOT NULL THEN COALESCE(ST_Y(p.lonlat::geometry),p.latitude::float8) ELSE COALESCE((SELECT AVG(ST_Y(lonlat::geometry)) FROM points WHERE visit_id=v.id),0) END,CASE WHEN a.id IS NOT NULL THEN a.longitude WHEN p.id IS NOT NULL THEN COALESCE(ST_X(p.lonlat::geometry),p.longitude::float8) ELSE COALESCE((SELECT AVG(ST_X(lonlat::geometry)) FROM points WHERE visit_id=v.id),0) END FROM visits v LEFT JOIN areas a ON a.id=v.area_id LEFT JOIN places p ON p.id=v.place_id WHERE v.id=$1",
            [id]
          ).rows

        if Dawarich.Geocoding.Config.resolve(repo).enabled && !(lat == 0 && lon == 0) do
          {:replay, "enabled nearby provider"}
        else
          {:ok, current_place(repo, visit.place_id)}
        end
      end
    end)
  end

  defp current_place(_repo, nil), do: []

  defp current_place(repo, id) do
    case repo.query!(
           "SELECT id,name,COALESCE(ST_Y(lonlat::geometry),latitude::float8),COALESCE(ST_X(lonlat::geometry),longitude::float8),geodata->'properties'->'osm_id',geodata->'properties'->'osm_type',geodata->'properties'->'osm_key',geodata->'properties'->'osm_value',city,country,CASE source WHEN 0 THEN 'manual' WHEN 1 THEN 'photon' WHEN 2 THEN 'gpx_waypoint' END,geodata FROM places WHERE id=$1",
           [id]
         ).rows do
      [row] ->
        [
          {:object,
           Enum.zip(
             ~w(id name latitude longitude osm_id osm_type osm_key osm_value city country source geodata),
             row
           )}
        ]

      [] ->
        []
    end
  end

  defp time(value, optional?) do
    cond do
      Ruby.blank?(value) ->
        if optional?, do: {:ok, nil}, else: invalid_time()

      is_binary(value) and value =~ ~r/\A[a-z]{2,}\z/ and
          String.downcase(value) not in @calendar_words ->
        invalid_time()

      true ->
        case Params.timestamp(value) do
          {:ok, {:text, text}} ->
            [[at]] = Repo.query!("SELECT $1::text::timestamptz AT TIME ZONE 'UTC'", [text]).rows
            {:ok, at}

          _ ->
            {:replay, "visit time parse shape"}
        end
    end
  end

  defp invalid_time, do: {:error, 400, "Invalid date format"}

  defp window(where, args, nil, _to), do: {where, args}
  defp window(where, args, _from, nil), do: {where, args}

  defp window(where, args, from, to) do
    n = length(args)
    {where <> " AND v.started_at >= $#{n + 1} AND v.started_at <= $#{n + 2}", args ++ [from, to]}
  end

  defp area(_params, false, where, args), do: {:ok, where, args}

  defp area(params, true, where, args) do
    with {:ok, sw_lat, sw_lon} <- Params.coordinates(params["sw_lat"], params["sw_lng"]),
         {:ok, ne_lat, ne_lon} <- Params.coordinates(params["ne_lat"], params["ne_lng"]) do
      n = length(args)
      envelope = "ST_MakeEnvelope($#{n + 1},$#{n + 2},$#{n + 3},$#{n + 4},4326)"

      place =
        "p.lonlat IS NOT NULL AND ST_Contains(#{envelope},ST_SetSRID(p.lonlat::geometry,4326))"

      area =
        "a.id IS NOT NULL AND ST_Contains(#{envelope},ST_SetSRID(ST_MakePoint(a.longitude,a.latitude),4326))"

      {:ok, where <> " AND ((#{place}) OR (#{area}))", args ++ [sw_lon, sw_lat, ne_lon, ne_lat]}
    end
  end

  defp page(params, where, args) do
    if Ruby.blank?(params["page"]) do
      {:ok, "", []}
    else
      with {:ok, page} <- Params.count(params["page"], 1),
           {:ok, per} <- Params.count(params["per_page"], 100),
           true <- per > 0 do
        page = max(page, 1)
        per = min(per, 500)
        total = Payload.count(where, args)

        headers = [
          {"x-current-page", to_string(page)},
          {"x-total-pages", to_string(div(total + per - 1, per))},
          {"x-total-count", to_string(total)}
        ]

        {:ok, " LIMIT #{per} OFFSET #{(page - 1) * per}", headers}
      else
        false -> {:replay, "visit page size"}
        replay -> replay
      end
    end
  end
end
