defmodule Dawarich.Ingest.Geo do
  @moduledoc false

  alias Dawarich.Ingest.Ruby
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Support

  @wkt ~r/\APOINT\s*\(\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\)\z/i
  @parts ~r/\APOINT\(([^\s()\[\],]*) ([^\s()\[\],]*)\)\z/
  @token ~r/\A[-+]?(\d+(\.\d*)?|\.\d+)(e[-+]?\d+)?\z/i
  @inside ~r/POINT[^(]*\(([^)]*)\)/i
  @numbers ~r/-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?/

  def wkt(lon, lat), do: "POINT(" <> Ruby.to_s(lon) <> " " <> Ruby.to_s(lat) <> ")"

  def null_island?(lon, lat), do: meters(Ruby.to_f(lat), Ruby.to_f(lon)) <= 5_000

  def null_island_wkt?(wkt) do
    case Regex.run(@wkt, wkt, capture: :all_but_first) do
      [lon, lat] -> null_island?(lon, lat)
      nil -> false
    end
  end

  def point(wkt) do
    with [a, b] <- Regex.run(@parts, wkt, capture: :all_but_first),
         true <- a =~ @token and b =~ @token,
         x when is_float(x) <- Support.to_f(a),
         y when is_float(y) <- Support.to_f(b) do
      {longitude(x), y |> min(90.0) |> max(-90.0)}
    else
      _ -> Ruby.unsupported!("WKT RGeo would not parse")
    end
  end

  def ewkb!(wkt) do
    {x, y} = point(wkt)

    Base.encode16(
      <<1, 0x20000001::little-32, 4326::little-32, x::little-float-64, y::little-float-64>>
    )
  end

  def dedup_key(payload) do
    raw = payload.lonlat || ""

    inside =
      with [match] <- Regex.run(@inside, raw, capture: :all_but_first),
           do: match,
           else: (_ -> raw)

    [lon, lat | _] =
      Enum.map(Regex.scan(@numbers, inside), fn [n] -> zero(Support.to_f(n)) end) ++ [nil, nil]

    {lon, lat, payload.timestamp, payload.user_id}
  end

  defp zero(value) when value == 0.0, do: 0.0
  defp zero(value), do: value

  def longitude(x) when x < -180.0 or x > 180.0 do
    m = :math.fmod(x, 360.0)
    m = if m < 0.0, do: m + 360.0, else: m
    if m > 180.0, do: m - 360.0, else: m
  end

  def longitude(x), do: x

  defp meters(lat, lon) do
    rad = :math.pi() / 180
    lat1 = lat * rad
    dlat = 0.0 - lat1
    dlon = 0.0 - lon * rad

    a =
      :math.pow(:math.sin(dlat / 2), 2) +
        :math.cos(lat1) * :math.pow(:math.sin(dlon / 2), 2) * :math.cos(0.0)

    2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a)) * 6371.0 * 1_000
  end
end
