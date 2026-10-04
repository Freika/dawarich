defmodule Dawarich.Admin.InstancePage do
  @moduledoc false

  alias Dawarich.ActiveRecordEncryption
  alias Dawarich.Geocoding.{Config, Providers}
  alias Dawarich.ReleaseMigrations.Effects.Support.{InstanceSettingsRegistry, Ruby}

  @sections %{
    "photon" => ~w(photon_api_host photon_api_key photon_api_use_https),
    "geoapify" => ~w(geoapify_api_key),
    "nominatim" => ~w(nominatim_api_host nominatim_api_key nominatim_api_use_https),
    "locationiq" => ~w(locationiq_api_key),
    "rate_limit" => ~w(reverse_geocoding_rps),
    "points" => ~w(store_geodata)
  }
  @https_only ~w(photon.dawarich.app photon.komoot.io app.chibigeo.com)

  def load(repo, env) do
    rows =
      repo.query!("SELECT key, value, encrypted_value FROM instance_settings", [], log: false).rows

    stored = Map.new(rows, fn [name, value, encrypted] -> {name, {value, encrypted}} end)

    key =
      case ActiveRecordEncryption.key(env) do
        {:ok, key} -> key
        _ -> nil
      end

    fields =
      Map.new(InstanceSettingsRegistry.definitions(), fn definition ->
        {elem(definition, 0), field(definition, stored, env, key)}
      end)

    locked = Providers.bare_host(fields["photon_api_host"].value) in @https_only
    fields = Map.update!(fields, "photon_api_use_https", &Map.put(&1, :locked_on, locked))

    fields =
      Map.new(fields, fn {name, field} ->
        {name,
         Map.merge(field, %{
           disabled: field.pinned or field.locked_on,
           hidden_false: field.kind == :boolean and not field.pinned and not field.locked_on
         })}
      end)

    geocoding = Config.resolve(repo, env) |> Map.delete(:api_key)

    [[legacy]] =
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM service_settings WHERE service = 0 AND active = true)",
        [],
        log: false
      ).rows

    {:ok,
     %{
       fields: fields,
       section_default: default_section(geocoding),
       geocoding: geocoding,
       legacy: legacy
     }}
  rescue
    _ -> :rails
  end

  def section(data, param) do
    if is_binary(param) and Map.has_key?(@sections, param), do: param, else: data.section_default
  end

  def section_keys(section), do: Map.fetch!(@sections, section)

  def section_status(data, section) do
    fields = Enum.map(section_keys(section), &Map.fetch!(data.fields, &1))

    cond do
      Enum.any?(fields, & &1.unreadable) ->
        :attention

      data.geocoding.enabled and to_string(Map.get(data.geocoding, :provider)) == section ->
        :in_use

      Enum.any?(fields, & &1.pinned) ->
        :pinned

      true ->
        nil
    end
  end

  defp default_section(%{enabled: true, provider: provider}), do: to_string(provider)
  defp default_section(_), do: "photon"

  defp field({name, var, kind, default} = definition, stored, env, key) do
    {plain, encrypted} = Map.get(stored, name, {nil, nil})
    {value, unreadable} = read(kind, plain, encrypted, key)

    {value, source} =
      cond do
        InstanceSettingsRegistry.set?(env[var]) ->
          {InstanceSettingsRegistry.coerce(definition, env[var]), :env}

        not is_nil(value) ->
          {value, :stored}

        true ->
          {default, :default}
      end

    present = Ruby.present?(value)
    pinned = source == :env

    %{
      key: name,
      env_var: var,
      kind: kind,
      source: source,
      pinned: pinned,
      value: if(kind == :secret, do: nil, else: value),
      display: if(kind == :secret, do: nil, else: display(value)),
      present: present,
      unreadable: unreadable,
      locked_on: false,
      clear: kind == :secret and (present or unreadable) and not pinned
    }
  end

  defp read(:secret, _plain, nil, _key), do: {nil, false}
  defp read(:secret, _plain, _encrypted, nil), do: {nil, true}

  defp read(:secret, _plain, encrypted, key) do
    case ActiveRecordEncryption.decrypt(encrypted, key) do
      {:ok, value} -> {value, false}
      _ -> {nil, true}
    end
  end

  defp read(_kind, plain, _encrypted, _key), do: {plain, false}

  defp display(value) when is_float(value) do
    if value == trunc(value), do: trunc(value), else: value
  end

  defp display(value), do: value
end
