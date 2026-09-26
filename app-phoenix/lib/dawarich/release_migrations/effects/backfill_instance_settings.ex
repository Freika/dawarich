defmodule Dawarich.ReleaseMigrations.Effects.BackfillInstanceSettings do
  @moduledoc false

  import Dawarich.ReleaseMigration, only: [exists?: 3]

  alias Dawarich.ActiveRecordEncryption

  alias Dawarich.ReleaseMigrations.Effects.Support.{
    InstanceSettingsRegistry,
    Ruby,
    ServiceSetting
  }

  @provider_keys ~w[photon_api_host geoapify_api_key nominatim_api_host locationiq_api_key]
  @key_for_host %{"photon" => "photon_api_host", "nominatim" => "nominatim_api_host"}
  @key_for_api_key %{
    "photon" => "photon_api_key",
    "nominatim" => "nominatim_api_key",
    "geoapify" => "geoapify_api_key",
    "locationiq" => "locationiq_api_key"
  }

  def provider_keys, do: @provider_keys

  def run(repo, env \\ System.get_env()) do
    key = ActiveRecordEncryption.key(env)
    copy_environment(repo, env, key)
    unless environment_names_a_provider?(env), do: copy_user_settings(repo, key)
    :ok
  end

  defp copy_environment(repo, env, key) do
    for {name, var, _kind, _default} = definition <- InstanceSettingsRegistry.definitions(),
        InstanceSettingsRegistry.set?(env[var]),
        do: store(repo, name, InstanceSettingsRegistry.coerce(definition, env[var]), key)
  end

  defp environment_names_a_provider?(env) do
    Enum.any?(@provider_keys, fn name ->
      Ruby.present?(Ruby.strip(env[InstanceSettingsRegistry.env_var(name)] || ""))
    end)
  end

  defp copy_user_settings(repo, key) do
    settings = ServiceSetting.active_geocoding(repo)

    if settings != [] do
      user_ids = Enum.map(settings, & &1.user_id)

      admins =
        repo.query!(
          "SELECT id FROM users WHERE deleted_at IS NULL AND id = ANY ($1) AND admin",
          [user_ids],
          log: false
        ).rows
        |> List.flatten()

      partial =
        exists?(repo, "SELECT 1 FROM users WHERE deleted_at IS NULL AND NOT (id = ANY ($1))", [
          user_ids
        ])

      signatures = Enum.map(settings, &signature(&1, key))
      admin_settings = Enum.filter(settings, &(&1.user_id in admins))

      cond do
        not partial and length(Enum.uniq(signatures)) == 1 ->
          write(repo, lowest_rate(settings), key)

        admin_settings != [] and
            length(Enum.uniq(Enum.map(admin_settings, &signature(&1, key)))) == 1 ->
          write(repo, lowest_rate(admin_settings), key)

        true ->
          :ok
      end
    end
  end

  defp signature(setting, key) do
    [
      setting.provider,
      Ruby.index(setting.config, "host"),
      Ruby.index(setting.config, "use_https"),
      safe_api_key(setting, key)
    ]
  end

  defp safe_api_key(setting, key) do
    case ServiceSetting.credentials(setting, key) do
      :unreadable -> :unreadable
      {:ok, _plaintext} -> ServiceSetting.api_key(setting, key)
    end
  end

  defp lowest_rate(settings), do: Enum.min_by(settings, &rate(Ruby.index(&1.config, "rps")))

  defp rate(value) do
    cond do
      Ruby.blank?(value) -> {2, 0}
      is_number(value) -> {1, value}
      is_binary(value) -> ordered(Ruby.to_f(value))
      true -> Ruby.no_method!("to_f", value)
    end
  end

  defp ordered(:infinity), do: {2, 0}
  defp ordered(:neg_infinity), do: {0, 0}
  defp ordered(value), do: {1, value}

  defp write(repo, setting, key) do
    config = setting.config
    host_key = @key_for_host[setting.provider]
    if host_key, do: store(repo, host_key, Ruby.index(config, "host"), key)

    store(repo, @key_for_api_key[setting.provider], safe_api_key(setting, key), key)

    if setting.provider == "photon",
      do: store(repo, "photon_api_use_https", Ruby.index(config, "use_https"), key)

    if setting.provider == "nominatim",
      do: store(repo, "nominatim_api_use_https", Ruby.index(config, "use_https"), key)

    store(repo, "reverse_geocoding_rps", Ruby.index(config, "rps"), key)
  end

  defp store(_repo, name, value, _key)
       when is_nil(name) or is_nil(value) or value in [:unreadable, "", [], {:object, []}] or
              value == %{},
       do: false

  defp store(repo, name, value, key) do
    if exists?(repo, "SELECT 1 FROM instance_settings WHERE key = $1", [name]) do
      false
    else
      {json, secret} =
        if InstanceSettingsRegistry.secret?(name),
          do: {nil, ActiveRecordEncryption.encrypt(Ruby.to_s(value), ServiceSetting.key!(key))},
          else: {json(value), nil}

      repo.query!(
        "INSERT INTO instance_settings (key, value, encrypted_value, created_at, updated_at) " <>
          "VALUES ($1, $2::text::jsonb, $3, now(), now())",
        [name, json, secret],
        log: false
      )

      true
    end
  end

  defp json(value), do: IO.iodata_to_binary(Ruby.json(value))
end
