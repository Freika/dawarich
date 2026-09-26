defmodule Dawarich.ReleaseMigrations.Effects.Support.GeocodingSchema do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.{Ruby, ServiceSetting}

  @host_required ~w[photon nominatim]
  @api_key_required ~w[geoapify locationiq]
  @names %{
    "photon" => "Photon",
    "geoapify" => "Geoapify",
    "nominatim" => "Nominatim",
    "locationiq" => "LocationIQ"
  }
  @komoot_host "photon.komoot.io"
  @chibigeo_bare_host "app.chibigeo.com"
  @https_only_hosts ~w[photon.dawarich.app photon.komoot.io app.chibigeo.com]
  @host_format ~r/\A[a-z0-9_][a-z0-9._-]*(:\d+)?(\/[a-z0-9._\/-]*)?\z/
  @messages %{
    host_required:
      "%{provider} needs a host. Enter your instance's hostname, for example photon.example.com.",
    host_invalid:
      "The host must be a bare hostname with an optional port or path — no http:// prefix, no spaces.",
    api_key_required: "%{provider} needs an API key.",
    chibigeo_api_key_required:
      "ChibiGeo needs an API key. The free Hobby plan includes 2,500 lookups per day — get your key at chibigeo.com."
  }

  def https_only_hosts, do: @https_only_hosts
  def messages, do: @messages

  def normalize(setting, key) do
    config = setting.config
    host = Ruby.index(config, "host")

    unless is_map(config),
      do:
        raise(
          Ruby.Unreproducible,
          "cannot reproduce Ruby's normalization of #{Ruby.instance(config)}"
        )

    config = if Ruby.blank?(host), do: config, else: Map.put(config, "host", normalize_host(host))
    host = Ruby.index(config, "host")

    config =
      if bare_host(host) in @https_only_hosts,
        do: Map.put(config, "use_https", true),
        else: config

    setting = %{setting | config: config}

    setting =
      if komoot?(setting.provider, host),
        do: ServiceSetting.drop_api_key(setting, key),
        else: setting

    case rate(setting.provider, host, Ruby.index(config, "rps")) do
      nil -> %{setting | config: Map.delete(config, "rps")}
      rps -> %{setting | config: Map.put(config, "rps", rps)}
    end
  end

  def validate(setting, key) do
    host = Ruby.index(setting.config, "host")
    name = @names[setting.provider]

    host_errors =
      cond do
        setting.provider in @host_required and Ruby.blank?(host) ->
          [String.replace(@messages.host_required, "%{provider}", name)]

        Ruby.present?(host) and not (is_binary(host) and host =~ @host_format) ->
          [@messages.host_invalid]

        true ->
          []
      end

    key_errors =
      if setting.provider in @api_key_required and
           Ruby.blank?(ServiceSetting.api_key(setting, key)),
         do: [String.replace(@messages.api_key_required, "%{provider}", name)],
         else: []

    chibigeo_errors =
      if chibigeo?(setting.provider, host) and Ruby.blank?(ServiceSetting.api_key(setting, key)),
        do: [@messages.chibigeo_api_key_required],
        else: []

    host_errors ++ key_errors ++ chibigeo_errors
  end

  def validate!(setting, key) do
    case validate(setting, key) do
      [] -> :ok
      errors -> raise Ruby.Error, "Validation failed: " <> Enum.join(errors, ", ")
    end
  end

  defp normalize_host(host) do
    host
    |> Ruby.to_s()
    |> Ruby.strip()
    |> String.downcase()
    |> String.replace(~r/\Ahttps?:\/\//, "")
    |> String.replace(~r/\/+\z/, "")
  end

  defp bare_host(host) when is_binary(host),
    do: host |> String.split("/") |> hd() |> String.split(":") |> hd()

  defp bare_host(_host), do: nil

  defp komoot?(provider, host), do: provider == "photon" and bare_host(host) == @komoot_host

  defp chibigeo?(provider, host),
    do: provider == "photon" and bare_host(host) == @chibigeo_bare_host

  defp rate(provider, host, value) do
    cond do
      komoot?(provider, host) -> 1.0
      chibigeo?(provider, host) -> clamp(number(value), 1.0, 1.0, 25.0)
      true -> clamp(number(value), nil, 0.1, 1000.0)
    end
  end

  defp number(value) when is_number(value), do: value / 1
  defp number(value) when is_binary(value), do: Ruby.float(value)
  defp number(_value), do: nil

  defp clamp(number, default, _min, _max) when number in [nil, :neg_infinity], do: default
  defp clamp(:infinity, _default, _min, max), do: max
  defp clamp(number, default, _min, _max) when number <= 0, do: default
  defp clamp(number, _default, min, max), do: number |> max(min) |> min(max)
end
