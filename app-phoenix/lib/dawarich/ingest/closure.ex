defmodule Dawarich.Ingest.Closure do
  @moduledoc false
  alias Dawarich.Ingest.{
    Cast,
    Friends,
    Geo,
    GeoJSON,
    OwnTracks,
    Ruby,
    Timestamp,
    Traccar,
    Unsupported
  }

  alias Dawarich.Imports.{DateParts, ImportTime, NormalCast}
  alias Dawarich.Imports.NormalCast.Text

  @failed %{
    points: "controllers.api.v1.points.point_creation_failed",
    overland: "controllers.api.v1.overland.batches.batch_creation_failed",
    owntracks: "controllers.api.v1.owntracks.points.point_creation_failed",
    traccar: "controllers.api.v1.traccar.points.point_creation_failed"
  }
  @strings ~w(tracker_id topic ssid bssid velocity ping external_track_id)a
  @arrays ~w(inrids in_regions)a

  def points_limit?(user) do
    key = "points_limit_exceeded/#{user.id}"

    case Dawarich.RailsCache.get(key) do
      {:ok, value} ->
        value not in [false, nil]

      _ ->
        value = (user.points_count || 0) >= 10_000_000

        bytes =
          Dawarich.RailsCache.Wire.encode_boolean(value,
            expires_at: System.os_time(:second) + 86400
          )

        Dawarich.Redis.cache_command(["SET", key, bytes, "EX", "86400"])
        value
    end
  end

  def prepare(action, params, actor) do
    {payloads, friends} =
      case action do
        :points -> {GeoJSON.points(params, actor, true), nil}
        :overland -> {GeoJSON.overland(params, true), nil}
        :owntracks -> {OwnTracks.payloads(params), Friends.for_user(actor)}
        :traccar -> {Traccar.payloads(params, true), nil}
      end

    prepared =
      payloads
      |> Enum.reject(&unusable?/1)
      |> Enum.map(&Map.put(&1, :user_id, actor))
      |> Enum.uniq_by(&Geo.dedup_key/1)
      |> Enum.map(&prepare_point/1)

    {:ok, prepared, friends}
  rescue
    error in Timestamp.Invalid -> {:error, 422, %{"error" => error.message}}
    _ -> {:error, 500, failed(action)}
  end

  def failed(action), do: %{"error" => Dawarich.I18n.en!(@failed[action])}

  defp unusable?(p),
    do: is_nil(p[:lonlat]) or is_nil(p[:timestamp]) or Geo.null_island_wkt?(p[:lonlat])

  defp prepare_point(p) do
    values = Map.new(p, fn {key, value} -> {key, cast(key, value)} end)

    combo =
      Enum.map(~w(tracker_id topic ssid bssid)a, &dimension(p[&1])) ++
        Enum.map(~w(connection trigger battery_status)a, &NormalCast.column(&1, p[&1])) ++
        Enum.map(@arrays, &regions(p, &1))

    %{payload: p, key: Geo.dedup_key(p), combo: combo, values: values}
  end

  defp dimension(nil), do: nil
  defp dimension(value) when is_list(value), do: dimension(List.last(value))
  defp dimension(value), do: Ruby.to_s(value)

  defp regions(p, key) do
    case Map.fetch(p, key) do
      :error ->
        []

      {:ok, nil} ->
        nil

      {:ok, value} ->
        value = if is_list(value), do: value, else: [value]

        Enum.map(value, fn
          nil -> nil
          value when is_binary(value) -> value
          value -> Ruby.to_s(value)
        end)
    end
  end

  defp cast(:lonlat, value), do: Geo.ewkb!(value)
  defp cast(key, value) when key in [:raw_data, :motion_data], do: Cast.column(key, value)
  defp cast(key, value) when key in @strings, do: Text.cast(value)
  defp cast(key, value) when key in @arrays, do: array(value)
  defp cast(key, value), do: NormalCast.column(key, value)
  defp array(nil), do: nil
  defp array(list) when is_list(list), do: Enum.map(list, &Text.cast/1)

  defp array(text) when is_binary(text),
    do: text |> Dawarich.Imports.NormalCast.ArrayLiteral.decode() |> array()

  defp array(_), do: nil

  def timestamp(value, kind) do
    if Ruby.blank?(value) do
      nil
    else
      timestamp_present(value, kind)
    end
  rescue
    _ -> if(kind == :points, do: raise(Timestamp.Invalid), else: nil)
  end

  defp timestamp_present(value, :points) do
    case numeric(value) do
      {:ok, value} -> range(value)
      :error -> range(parse_datetime(value))
    end
  end

  defp timestamp_present(value, :traccar) do
    case numeric(value) do
      {:ok, value} -> if(value > 10_000_000_000, do: div(value, 1000), else: value)
      :error -> parse_datetime(value)
    end
  end

  defp numeric(value) do
    text = Ruby.to_s(value)
    if text =~ ~r/\A-?\d+\z/, do: {:ok, String.to_integer(text)}, else: :error
  end

  defp parse_datetime(value) do
    text = Ruby.to_s(value)

    try do
      Timestamp.points(text)
    rescue
      Unsupported ->
        fields = DateParts.parse(text)

        if Enum.all?(~w(year mon mday), &Map.has_key?(fields, &1)),
          do: Date.new!(fields["year"], fields["mon"], fields["mday"])

        case ImportTime.parse(text, "Etc/UTC", DateTime.utc_now()) do
          nil -> raise Timestamp.Invalid
          epoch -> epoch
        end
    end
  end

  defp range(value) when is_integer(value) and value >= -2_147_483_648 and value <= 2_147_483_647,
    do: value

  defp range(_), do: raise(Timestamp.Invalid)
end
