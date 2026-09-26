defmodule Dawarich.ReleaseMigrations.Effects.SeedGeocodingFromEnv do
  @moduledoc false

  import Dawarich.ReleaseMigration, only: [self_hosted?: 0, exists?: 3]

  alias Dawarich.ActiveRecordEncryption

  alias Dawarich.ReleaseMigrations.Effects.Support.{
    GeocodingSchema,
    InstanceSettingsRegistry,
    Ruby,
    ServiceSetting
  }

  def run(repo, env \\ System.get_env()) do
    if self_hosted?() and reverse_geocoding_enabled?(env) do
      attributes = env_provider_attributes(env)
      key = ActiveRecordEncryption.key(env)

      repo.query!("SELECT id FROM users WHERE deleted_at IS NULL ORDER BY id", [], log: false).rows
      |> Enum.reduce(nil, fn [user_id], restore ->
        try do
          Enum.each(attributes, &create_setting(repo, user_id, &1, key))
          winner_restore = activate_chain_winner(repo, user_id, key)
          restore || winner_restore
        rescue
          error ->
            reraise(if(restore, do: %Ruby.Error{message: restore}, else: error), __STACKTRACE__)
        end
      end)
    end

    :ok
  end

  def reverse_geocoding_enabled?(env) do
    Enum.any?(
      ~w[photon_api_host geoapify_api_key nominatim_api_host locationiq_api_key],
      &Ruby.present?(InstanceSettingsRegistry.resolve(env, &1))
    )
  end

  def env_provider_attributes(env) do
    photon_host = InstanceSettingsRegistry.resolve(env, "photon_api_host")

    [
      Ruby.present?(photon_host) &&
        {"photon", env["PHOTON_API_KEY"],
         %{"host" => env["PHOTON_API_HOST"], "use_https" => photon_use_https?(env, photon_host)}},
      Ruby.present?(InstanceSettingsRegistry.resolve(env, "geoapify_api_key")) &&
        {"geoapify", env["GEOAPIFY_API_KEY"], %{}},
      Ruby.present?(InstanceSettingsRegistry.resolve(env, "nominatim_api_host")) &&
        {"nominatim", env["NOMINATIM_API_KEY"],
         %{
           "host" => env["NOMINATIM_API_HOST"],
           "use_https" => Map.get(env, "NOMINATIM_API_USE_HTTPS", "true") == "true"
         }},
      Ruby.present?(InstanceSettingsRegistry.resolve(env, "locationiq_api_key")) &&
        {"locationiq", env["LOCATIONIQ_API_KEY"], %{}}
    ]
    |> Enum.filter(& &1)
  end

  defp photon_use_https?(env, photon_host) do
    normalized = photon_host |> Ruby.strip() |> String.downcase() |> String.split(":") |> hd()

    normalized in GeocodingSchema.https_only_hosts() or
      InstanceSettingsRegistry.resolve(env, "photon_api_use_https")
  end

  defp create_setting(repo, user_id, {provider, api_key, config}, key) do
    unless geocoding_exists?(repo, user_id, "provider = $2", [provider]) do
      setting =
        ServiceSetting.new(user_id, provider, config, api_key) |> GeocodingSchema.normalize(key)

      if GeocodingSchema.validate(setting, key) == [] and encryptable?(setting, key),
        do: ServiceSetting.insert!(repo, setting, key)
    end
  rescue
    error in [Ruby.Error, Postgrex.Error] -> {:skipped, error}
  end

  defp encryptable?(%{credentials: {:assigned, nil}}, _key), do: true
  defp encryptable?(_setting, key), do: match?({:ok, _}, key)

  defp activate_chain_winner(repo, user_id, key) do
    unless geocoding_exists?(repo, user_id, "active = TRUE", []) do
      case Enum.find_value(ServiceSetting.chain(), &ServiceSetting.find_by(repo, user_id, &1)) do
        nil -> nil
        winner -> ServiceSetting.activate!(repo, winner, key)
      end
    end
  end

  defp geocoding_exists?(repo, user_id, condition, params) do
    exists?(
      repo,
      "SELECT 1 FROM service_settings WHERE user_id = $1 AND service = 0 AND #{condition}",
      [user_id | params]
    )
  end
end
