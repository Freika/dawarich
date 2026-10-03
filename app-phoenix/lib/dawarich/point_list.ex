defmodule Dawarich.PointList do
  @moduledoc false

  alias Dawarich.{Entitlements, PointListWindow, Repo, TripSettings, UserTimeZone}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.TripsGate

  @per_page 50
  @max_page div(9_223_372_036_854_775_807, @per_page) + 1
  @filters ~w(start_at end_at import_id order_by page)
  @where """
  WHERE p.user_id = $1 AND ($2::bigint IS NULL OR p.import_id = $2)
    AND p.timestamp BETWEEN $3::bigint AND $4::bigint
    AND ($5::bigint IS NULL OR p.timestamp >= $5)
  """
  @columns ~w(id timestamp velocity city country country_name geodata lat lon)a
  @rows """
  SELECT p.id, p.timestamp, p.velocity, p.city, p.country, p.country_name, p.geodata,
         ST_Y(p.lonlat::geometry), ST_X(p.lonlat::geometry),
         to_timestamp(p.timestamp) AT TIME ZONE 'UTC',
         extract(epoch FROM (to_timestamp(p.timestamp) AT TIME ZONE z.name) -
           (to_timestamp(p.timestamp) AT TIME ZONE 'UTC'))::int
  FROM public.points p CROSS JOIN z
  """
  @cutoff """
  SELECT extract(epoch FROM (((($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE z.name)
    - interval '12 months') AT TIME ZONE z.name))::bigint FROM z
  """

  def address(user, id) do
    case Repo.query!("SELECT id, geodata FROM public.points WHERE user_id = $1 AND id = $2", [
           user.id,
           id
         ]).rows do
      [[id, geodata]] -> {:ok, %{id: id, geodata: geodata}}
      _ -> :rails
    end
  end

  def load(user, params, now, opts) do
    page = TripsGate.page_number(params["page"])

    with true <- valid_params?(params) and page <= @max_page and settings?(user.settings),
         {:ok, imports} <- imports(user.id),
         {:ok, import_id} <- selected_import(params["import_id"], imports),
         window =
           PointListWindow.build(params, user.settings, now, import_range(user.id, import_id)),
         true <- TripSettings.zone?(user.settings, window.zone) do
      cutoff = cutoff(user, now, opts)
      args = [user.id, import_id, window.start_epoch, window.end_epoch, cutoff]

      [[count, distinct]] =
        Repo.query!(
          "SELECT count(*), count(DISTINCT p.timestamp) FROM public.points p " <> @where,
          args
        ).rows

      if count == distinct do
        order = String.upcase(params["order_by"] || "desc")
        sql = @rows <> @where <> " ORDER BY p.timestamp #{order} LIMIT #{@per_page} OFFSET $6"
        rows = UserTimeZone.query!(sql, args ++ [(page - 1) * @per_page], user.settings).rows

        {:ok,
         %{
           window: window,
           rows: Enum.map(rows, &row(&1, window.zone)),
           imports: imports,
           count: count,
           page: page,
           total_pages: div(count + @per_page - 1, @per_page),
           geocoding:
             Dawarich.Geocoding.Config.resolve(Repo, Keyword.get(opts, :env, System.get_env())).enabled
         }}
      else
        :rails
      end
    else
      _ -> :rails
    end
  end

  def valid_params?(params) do
    Enum.all?(params, fn {key, value} ->
      key in @filters and (is_nil(value) or is_binary(value))
    end) and
      params["order_by"] in [nil, "asc", "desc", "ASC", "DESC"]
  end

  defp settings?(%{} = settings) do
    (is_nil(settings["timezone"]) or is_binary(settings["timezone"])) and
      case settings["maps"] do
        nil -> true
        %{} = maps -> maps["distance_unit"] in [nil, "km", "mi"]
        _ -> false
      end
  end

  defp settings?(_), do: false

  defp imports(user_id) do
    rows =
      Repo.query!(
        "SELECT id, name, created_at FROM public.imports WHERE user_id = $1 ORDER BY created_at DESC",
        [user_id]
      ).rows

    stamps = Enum.map(rows, &List.last/1)

    if length(stamps) == length(Enum.uniq(stamps)),
      do: {:ok, Enum.map(rows, fn [id, name, at] -> %{id: id, name: name, created_at: at} end)},
      else: :rails
  end

  defp selected_import(value, imports) do
    cond do
      Ruby.blank?(value) ->
        {:ok, nil}

      Regex.match?(~r/\A[0-9]{1,18}\z/, value) ->
        id = String.to_integer(value)
        if Enum.any?(imports, &(&1.id == id)), do: {:ok, id}, else: :rails

      true ->
        :rails
    end
  end

  defp import_range(_user_id, nil), do: nil

  defp import_range(user_id, import_id) do
    [[first, last]] =
      Repo.query!(
        "SELECT min(timestamp), max(timestamp) FROM public.points WHERE user_id = $1 AND import_id = $2",
        [user_id, import_id]
      ).rows

    if is_nil(first), do: nil, else: {first, last}
  end

  defp cutoff(user, now, opts) do
    if Entitlements.full_access?(user, Keyword.fetch!(opts, :self_hosted), now) do
      nil
    else
      [[epoch]] = UserTimeZone.query!(@cutoff, [DateTime.to_naive(now)], user.settings).rows
      epoch
    end
  end

  defp row(values, zone) do
    {display, [at, offset]} = Enum.split(values, length(@columns))

    Map.new(Enum.zip(@columns, display))
    |> Map.put(:recorded, UserTimeZone.zoned(at, offset, zone))
  end
end
