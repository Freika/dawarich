defmodule Dawarich.Geocoding.Providers do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def bare_host(nil), do: nil

  def bare_host(host) do
    case host |> to_string() |> String.split("/") |> hd() do
      "" -> nil
      first -> first |> String.split(":") |> hd()
    end
  end

  def komoot?(provider, host), do: provider == :photon and bare_host(host) == "photon.komoot.io"
  def chibigeo?(provider, host), do: provider == :photon and bare_host(host) == "app.chibigeo.com"
  def host_required?(provider), do: provider in [:photon, :nominatim]
  def api_key_required?(provider), do: provider in [:geoapify, :locationiq]

  def metered_per_key?(provider, host),
    do: api_key_required?(provider) or chibigeo?(provider, host)

  def key_digest(%{provider: provider, host: host, api_key: key}) do
    if metered_per_key?(provider, host) and Ruby.present?(key),
      do: :crypto.hash(:sha256, key) |> Base.encode16(case: :lower) |> binary_part(0, 12)
  end

  def rps(provider, host, value) do
    cond do
      komoot?(provider, host) -> 1.0
      chibigeo?(provider, host) -> clamp(number(value), 1.0, 1.0, 25.0)
      true -> clamp(number(value), nil, 0.1, 1000.0)
    end
  end

  defp clamp(nil, default, _min, _max), do: default
  defp clamp(n, default, _min, _max) when n <= 0, do: default
  defp clamp(n, _default, min, max), do: n |> max(min) |> min(max)

  defp number(value) when is_number(value), do: value * 1.0

  defp number(value) when is_binary(value),
    do: if(Ruby.strip(value) == "", do: nil, else: Ruby.float(value))

  defp number(_value), do: nil
end
