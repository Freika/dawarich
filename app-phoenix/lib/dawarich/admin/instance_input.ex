defmodule Dawarich.Admin.InstanceInput do
  @moduledoc false
  alias Dawarich.Geocoding.Providers
  alias Dawarich.I18n
  alias Dawarich.ReleaseMigrations.Effects.Support.{InstanceSettingsRegistry, Ruby}

  @hosts ~w(photon_api_host nominatim_api_host)
  @host_format ~r/\A[a-z0-9_][a-z0-9._-]*(:\d+)?(\/[a-z0-9._\/-]*)?\z/

  def prepare(params, resolved, env, locale) do
    clear = Map.get(params, "instance_settings_clear", %{})

    values =
      for {key, raw} <- Map.get(params, "instance_settings", []),
          definition = List.keyfind(InstanceSettingsRegistry.current_definitions(), key, 0),
          definition != nil,
          elem(definition, 2) != :secret or Ruby.strip(raw || "") != "" or
            Ruby.present?(clear[key]),
          do: {key, coerce(definition, raw)}

    values = Enum.map(values, fn {key, value} -> {key, normalize(key, value)} end)

    errors =
      if Enum.any?(values, fn {key, value} ->
           key in @hosts and Ruby.present?(value) and not Regex.match?(@host_format, value)
         end),
         do: [message(locale, "host_invalid")],
         else: []

    host = value(values, "photon_api_host", resolved, env)

    values =
      if List.keymember?(values, "photon_api_host", 0) and Providers.komoot?(:photon, host) and
           not InstanceSettingsRegistry.set?(env["PHOTON_API_KEY"]),
         do: put(values, "photon_api_key", nil),
         else: values

    errors =
      if Enum.any?(values, fn {key, _} -> key in ~w(photon_api_host photon_api_key) end) and
           Providers.chibigeo?(:photon, host) and
           not Ruby.present?(value(values, "photon_api_key", resolved, env)),
         do: errors ++ [message(locale, "chibigeo_key_required")],
         else: errors

    errors = errors ++ experimental_errors(values, resolved, env, locale)

    if errors == [], do: {:ok, values}, else: {:invalid, Enum.join(errors, " ")}
  end

  defp experimental_errors(values, resolved, env, locale) do
    url = experimental_value(values, "atlas_url", resolved, env)
    enabled = experimental_value(values, "map_matching_enabled", resolved, env)

    errors =
      if Ruby.present?(url) and not atlas_url?(url),
        do: [message(locale, "atlas_url_invalid")],
        else: []

    if enabled == true and not Ruby.present?(url),
      do: errors ++ [message(locale, "atlas_url_required")],
      else: errors
  end

  defp experimental_value(values, key, resolved, env) do
    definition = InstanceSettingsRegistry.fetch(key)
    raw = env[InstanceSettingsRegistry.env_var(key)]

    if InstanceSettingsRegistry.set?(raw),
      do: InstanceSettingsRegistry.coerce(definition, raw),
      else: value(values, key, resolved, env)
  end

  defp atlas_url?(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host, userinfo: nil, query: nil, fragment: nil}}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  defp coerce({_, _, _, default} = definition, raw) do
    if Ruby.strip(raw || "") == "",
      do: default,
      else: InstanceSettingsRegistry.coerce(definition, raw)
  end

  defp normalize(key, value) when key in @hosts and is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/\Ahttps?:\/\//, "")
    |> String.replace(~r/\/+\z/, "")
  end

  defp normalize(_, value), do: value

  defp value(values, key, resolved, env) do
    case List.keyfind(values, key, 0) do
      {_, value} ->
        value

      nil ->
        definition = InstanceSettingsRegistry.fetch(key)
        raw = env[InstanceSettingsRegistry.env_var(key)]

        if InstanceSettingsRegistry.set?(raw),
          do: InstanceSettingsRegistry.coerce(definition, raw),
          else: Map.get(resolved, key, elem(definition, 3))
    end
  end

  defp put(values, key, value) do
    if List.keymember?(values, key, 0),
      do: List.keyreplace(values, key, 0, {key, value}),
      else: values ++ [{key, value}]
  end

  defp message(locale, key) do
    {:ok, message} = I18n.t(locale, "admin.settings.update." <> key)
    message
  end
end
