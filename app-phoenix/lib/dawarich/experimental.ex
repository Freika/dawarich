defmodule Dawarich.Experimental do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.ReleaseMigrations.Effects.Support.InstanceSettingsRegistry, as: Registry

  require Logger
  @cache_ttl_ms 30_000

  @entries [
    %{
      key: :map_matching,
      label: "admin.settings.show.map_matching.title",
      description: "admin.settings.show.map_matching.description",
      toggles: [:map_matching_enabled, :map_matching_shadow_mode],
      config: [:atlas_url],
      prerequisites: %{map_matching_enabled: [:atlas_url]},
      env: %{
        map_matching_enabled: "MAP_MATCHING_ENABLED",
        map_matching_shadow_mode: "MAP_MATCHING_SHADOW_MODE",
        atlas_url: "ATLAS_URL"
      }
    }
  ]

  def entries, do: @entries

  def create_cache_table,
    do: :ets.new(__MODULE__, [:named_table, :public, :set, read_concurrency: true])

  def cached_map_matching?(repo \\ Repo) do
    case :ets.lookup(__MODULE__, repo) do
      [{^repo, enabled, loaded_at, :idle} = entry] ->
        if System.monotonic_time(:millisecond) - loaded_at >= @cache_ttl_ms do
          pending = put_elem(entry, 3, make_ref())
          if replace_cache(entry, pending) == 1, do: spawn(fn -> reload(repo, pending) end)
        end

        enabled

      [{^repo, enabled, _, _}] ->
        enabled

      [] ->
        :ets.insert_new(
          __MODULE__,
          {repo, false, System.monotonic_time(:millisecond) - @cache_ttl_ms, :idle}
        )

        cached_map_matching?(repo)
    end
  end

  def refresh_map_matching(repo \\ Repo, env \\ System.get_env()) do
    cache_map_matching(repo, load_map_matching(repo, env))
  end

  def cache_map_matching(repo, enabled, loaded_at \\ System.monotonic_time(:millisecond)) do
    :ets.insert(__MODULE__, {repo, enabled, loaded_at, :idle})
    enabled
  end

  defp reload(repo, pending) do
    enabled =
      try do
        load_map_matching(repo, System.get_env())
      rescue
        _ -> refresh_failed(pending)
      catch
        _, _ -> refresh_failed(pending)
      end

    replace_cache(pending, {repo, enabled, System.monotonic_time(:millisecond), :idle})
  end

  defp refresh_failed(pending) do
    Logger.warning("map_matching.cache_refresh_failed")
    elem(pending, 1)
  end

  defp replace_cache(previous, updated) do
    :ets.select_replace(__MODULE__, [
      {{:"$1", :"$2", :"$3", :"$4"}, [{:"=:=", :"$_", {:const, previous}}],
       [
         {{:"$1", {:const, elem(updated, 1)}, {:const, elem(updated, 2)},
           {:const, elem(updated, 3)}}}
       ]}
    ])
  end

  defp load_map_matching(repo, env) do
    keys = ~w(map_matching_enabled atlas_url)
    unpinned = Enum.reject(keys, &Registry.set?(env[Registry.env_var(&1)]))

    stored =
      if unpinned == [] or
           (Registry.resolve(env, "map_matching_enabled") == false and
              pinned?(:map_matching_enabled, env)) do
        %{}
      else
        repo.query!("SELECT key,value FROM instance_settings WHERE key=ANY($1)", [unpinned],
          log: false
        ).rows
        |> Map.new(fn [key, value] -> {key, value} end)
      end

    values =
      Map.new(keys, fn key ->
        value =
          if Registry.set?(env[Registry.env_var(key)]),
            do: Registry.resolve(env, key),
            else: Map.get(stored, key) || elem(Registry.fetch(key), 3)

        {key, value}
      end)

    values["map_matching_enabled"] == true and values["atlas_url"] not in [nil, false, ""]
  end

  def value(setting, repo \\ Repo, env \\ System.get_env()) do
    name = Atom.to_string(setting)
    definition = Registry.fetch(name)
    raw = env[Registry.env_var(name)]

    if Registry.set?(raw) do
      Registry.coerce(definition, raw)
    else
      case repo.query!("SELECT value FROM instance_settings WHERE key=$1", [name], log: false).rows do
        [[value]] when not is_nil(value) -> value
        _ -> elem(definition, 3)
      end
    end
  end

  def pinned?(setting, env \\ System.get_env()),
    do: Registry.set?(env[Registry.env_var(Atom.to_string(setting))])

  def enabled?(key, repo \\ Repo, env \\ System.get_env()) do
    entry = Enum.find(@entries, &(&1.key == key)) || raise(KeyError, key: key)
    toggle = hd(entry.toggles)

    value(toggle, repo, env) == true and
      Enum.all?(Map.get(entry.prerequisites, toggle, []), fn setting ->
        value(setting, repo, env) not in [nil, false, ""]
      end)
  end

  def map_matching?(repo \\ Repo, env \\ System.get_env()),
    do: enabled?(:map_matching, repo, env)

  def map_matching_visible?(repo \\ Repo, env \\ System.get_env()),
    do: map_matching?(repo, env) and not value(:map_matching_shadow_mode, repo, env)
end
