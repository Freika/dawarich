defmodule Dawarich.UserTimeZone do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Repo

  @utc_zones ~w(UTC Etc/UTC UCT Etc/UCT Universal Etc/Universal Zulu Etc/Zulu)

  def local(settings, %NaiveDateTime{} = at) do
    %{rows: [[offset, zone]]} =
      query!(
        "SELECT extract(epoch FROM (($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE z.name) - $1::timestamp)::int, z.name FROM z",
        [at],
        settings
      )

    zoned(at, offset, zone)
  end

  def zoned(at, offset, zone),
    do: %{local: NaiveDateTime.add(at, offset), offset: offset, utc: zone in @utc_zones}

  def name(settings, repo \\ Repo) do
    %{rows: [[name]]} = query!("SELECT name FROM z", [], settings, repo)
    name
  end

  def iana(repo, settings, env \\ System.get_env()) do
    effective = zone(settings, env)
    raw = if Ruby.present?(effective), do: effective, else: env["TIME_ZONE"] || "Europe/Berlin"

    case repo.query!(
           "SELECT name FROM pg_timezone_names WHERE name = $1",
           [Dawarich.TimeZoneName.to_iana(raw)],
           log: false
         ).rows do
      [[name] | _] -> name
      [] -> "Etc/UTC"
    end
  end

  def query!(sql, params, settings, repo_or_env \\ Repo)

  def query!(sql, params, settings, env) when is_map(env),
    do: query!(sql, params, settings, Repo, env)

  def query!(sql, params, settings, repo),
    do: query!(sql, params, settings, repo, System.get_env())

  def query!(sql, params, settings, repo, env) do
    n = length(params)

    repo.query!(
      """
      WITH z AS MATERIALIZED (SELECT coalesce(
        (SELECT name FROM pg_timezone_names WHERE name = $#{n + 1}),
        (SELECT name FROM pg_timezone_names WHERE name = $#{n + 2}),
        'UTC') AS name)
      """ <> sql,
      params ++
        [
          Dawarich.TimeZoneName.to_iana(zone(settings, env)),
          Dawarich.TimeZoneName.to_iana(env["TIME_ZONE"] || "Europe/Berlin")
        ]
    )
  end

  def zone(settings, env \\ System.get_env())
  def zone(%{"timezone" => zone}, _env) when is_binary(zone), do: zone
  def zone(_settings, env), do: env["TIME_ZONE"] || "UTC"
end
