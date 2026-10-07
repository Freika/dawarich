defmodule Dawarich.Experimental do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.ReleaseMigrations.Effects.Support.InstanceSettingsRegistry, as: Registry

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

  def cached_map_matching?(repo \\ Repo),
    do: :persistent_term.get({__MODULE__, repo, :map_matching}, false)

  def refresh_map_matching(repo \\ Repo, env \\ System.get_env()) do
    enabled = map_matching?(repo, env)
    :persistent_term.put({__MODULE__, repo, :map_matching}, enabled)
    enabled
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
