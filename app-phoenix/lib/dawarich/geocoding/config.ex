defmodule Dawarich.Geocoding.Config do
  @moduledoc false

  alias Dawarich.ActiveRecordEncryption
  alias Dawarich.Geocoding.Providers
  alias Dawarich.ReleaseMigrations.Effects.Support.{InstanceSettingsRegistry, Ruby}

  @chain [
    photon: "photon_api_host",
    geoapify: "geoapify_api_key",
    nominatim: "nominatim_api_host",
    locationiq: "locationiq_api_key"
  ]
  @https_only ~w(photon.dawarich.app photon.komoot.io app.chibigeo.com)

  def resolve(repo, env \\ System.get_env()) do
    get = getter(repo, env)

    candidates =
      for {provider, key} <- @chain,
          {value, source} = get.(key),
          Ruby.present?(value),
          do: {provider, value, source}

    case Enum.find(candidates, &match?({_, _, :env}, &1)) || List.first(candidates) do
      nil -> %{enabled: false, store_geodata: truthy?(elem(get.("store_geodata"), 0))}
      {provider, primary, source} -> build(provider, primary, source, get)
    end
  end

  defp build(provider, primary, source, get) do
    value = &elem(get.(&1), 0)

    {host, api_key, https} =
      case provider do
        :photon ->
          {primary, value.("photon_api_key"),
           Providers.bare_host(primary) in @https_only or truthy?(value.("photon_api_use_https"))}

        :nominatim ->
          {primary, value.("nominatim_api_key"), value.("nominatim_api_use_https")}

        _ ->
          {nil, primary, true}
      end

    %{
      enabled: true,
      source: source,
      provider: provider,
      host: host,
      api_key: api_key,
      use_https: https,
      rps: Providers.rps(provider, host, value.("reverse_geocoding_rps")),
      store_geodata: truthy?(value.("store_geodata"))
    }
  end

  defp getter(repo, env) do
    stored = stored(repo, env)

    fn key ->
      definition = InstanceSettingsRegistry.fetch(key)
      raw = env[InstanceSettingsRegistry.env_var(key)]

      cond do
        InstanceSettingsRegistry.set?(raw) ->
          {InstanceSettingsRegistry.coerce(definition, raw), :env}

        Map.has_key?(stored, key) ->
          {Map.fetch!(stored, key), :stored}

        true ->
          {elem(definition, 3), :default}
      end
    end
  end

  defp stored(repo, env) do
    key = with {:ok, key} <- ActiveRecordEncryption.key(env), do: key, else: (_ -> nil)

    %{rows: rows} =
      repo.query!("SELECT key, value, encrypted_value FROM instance_settings", [], log: false)

    for [name, value, encrypted] <- rows,
        List.keymember?(InstanceSettingsRegistry.definitions(), name, 0),
        read <- [read(name, value, encrypted, key)],
        not is_nil(read),
        into: %{},
        do: {name, read}
  end

  defp read(name, value, encrypted, key) do
    cond do
      not InstanceSettingsRegistry.secret?(name) ->
        value

      is_nil(encrypted) or is_nil(key) ->
        nil

      true ->
        with {:ok, clear} <- ActiveRecordEncryption.decrypt(encrypted, key),
             do: clear,
             else: (_ -> nil)
    end
  end

  defp truthy?(value), do: value not in [nil, false]
end
