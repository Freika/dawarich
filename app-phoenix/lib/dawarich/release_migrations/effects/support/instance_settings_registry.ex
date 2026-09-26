defmodule Dawarich.ReleaseMigrations.Effects.Support.InstanceSettingsRegistry do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @definitions [
    {"photon_api_host", "PHOTON_API_HOST", :string, nil},
    {"photon_api_key", "PHOTON_API_KEY", :secret, nil},
    {"photon_api_use_https", "PHOTON_API_USE_HTTPS", :boolean, false},
    {"nominatim_api_host", "NOMINATIM_API_HOST", :string, nil},
    {"nominatim_api_key", "NOMINATIM_API_KEY", :secret, nil},
    {"nominatim_api_use_https", "NOMINATIM_API_USE_HTTPS", :boolean, true},
    {"geoapify_api_key", "GEOAPIFY_API_KEY", :secret, nil},
    {"locationiq_api_key", "LOCATIONIQ_API_KEY", :secret, nil},
    {"reverse_geocoding_rps", "REVERSE_GEOCODING_RPS", :float, nil},
    {"store_geodata", "STORE_GEODATA", :boolean, true}
  ]

  def definitions, do: @definitions

  def fetch(key), do: List.keyfind(@definitions, key, 0) || raise(KeyError, key: key)

  def secret?(key), do: elem(fetch(key), 2) == :secret

  def env_var(key), do: elem(fetch(key), 1)

  def set?(raw), do: Ruby.strip(raw || "") != ""

  def resolve(env, key) do
    {_key, var, _kind, default} = definition = fetch(key)
    if set?(env[var]), do: coerce(definition, env[var]), else: default
  end

  def coerce({_key, _var, kind, default}, raw) do
    value = Ruby.strip(raw)

    case kind do
      kind when kind in [:string, :secret] -> value
      :boolean -> value == "true"
      :float -> Ruby.float(value) || default
    end
  end
end
