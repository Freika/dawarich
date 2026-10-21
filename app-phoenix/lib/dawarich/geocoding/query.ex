defmodule Dawarich.Geocoding.Query do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.{Ruby, RubyFloat}

  def build(config, {lat, lon}, opts, version) do
    {base, params} = request(config, lat, lon, opts)
    params = Enum.reject(params, fn {_name, value} -> is_nil(value) end)
    cached = Enum.reject(params, fn {name, _value} -> name =~ ~r/(key|token)/ end)
    {base <> encode(params), base <> encode(cached), headers(config, version)}
  end

  defp request(%{provider: :photon} = c, lat, lon, opts) do
    {"#{scheme(c.use_https)}://#{c.host || "photon.komoot.io"}/reverse?",
     [
       {"lang", "en"},
       {"limit", opts[:limit]},
       {"lat", lat},
       {"lon", lon},
       {"radius", opts[:radius]},
       {"distance_sort", if(opts[:distance_sort], do: "true")}
     ]}
  end

  defp request(%{provider: :geoapify} = c, lat, lon, opts),
    do:
      {"https://api.geoapify.com/v1/geocode/reverse?",
       [
         {"apiKey", c.api_key},
         {"lang", "en"},
         {"limit", opts[:limit]},
         {"lat", lat},
         {"lon", lon}
       ]}

  defp request(%{provider: :nominatim} = c, lat, lon, _opts) do
    host = c.host || "nominatim.openstreetmap.org"
    https = if host == "nominatim.openstreetmap.org", do: true, else: c.use_https
    {"#{scheme(https)}://#{host}/reverse?", nominatim(lat, lon)}
  end

  defp request(%{provider: :locationiq} = c, lat, lon, _opts),
    do: {"https://us1.locationiq.com/v1/reverse.php?", [{"key", c.api_key} | nominatim(lat, lon)]}

  defp nominatim(lat, lon),
    do: [
      {"format", "json"},
      {"addressdetails", "1"},
      {"accept-language", "en"},
      {"lat", lat},
      {"lon", lon}
    ]

  defp scheme(value) when value in [nil, false], do: "http"
  defp scheme(_value), do: "https"

  defp encode(params) do
    params
    |> Enum.map(fn {name, value} ->
      URI.encode_www_form(name) <> "=" <> URI.encode_www_form(text(value))
    end)
    |> Enum.sort()
    |> Enum.join("&")
  end

  defp text(value) when is_float(value), do: RubyFloat.to_s(value)
  defp text(value) when is_integer(value), do: Integer.to_string(value)
  defp text(value) when is_binary(value), do: value

  defp headers(config, version) do
    base = [{"user-agent", "Dawarich #{version} (https://dawarich.app)"}, {"accept", "*/*"}]

    if config.provider == :photon and Ruby.present?(config.api_key),
      do: base ++ [{"x-api-key", config.api_key}],
      else: base
  end
end
