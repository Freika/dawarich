defmodule Dawarich.RailsTime do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.TimeZoneName

  @zone ~r{\A[A-Z][A-Za-z_\-]*(?:/[A-Za-z0-9_+\-]+)+\z}

  def iso8601(nil, _setting), do: {:ok, nil}

  def iso8601(%NaiveDateTime{} = utc, setting) do
    with_zone(setting, fn ->
      [[text]] = Repo.query!("SELECT " <> sql("$1::timestamp", 0), [utc]).rows
      {:ok, text}
    end)
  end

  def with_zone(setting, fun) do
    with_zone(Repo, setting, fun)
  end

  def with_zone(repo, setting, fun) do
    setting = if is_nil(setting), do: System.get_env("TIME_ZONE", "UTC"), else: setting
    zone = if is_binary(setting), do: TimeZoneName.to_iana(setting), else: setting

    if is_binary(zone) and zone =~ @zone do
      repo.transaction(fn ->
        case set_zone(repo, zone) do
          :ok -> fun.()
          replay -> repo.rollback(replay)
        end
      end)
      |> case do
        {:ok, result} -> result
        {:error, replay} -> replay
      end
    else
      {:replay, "time zone setting #{inspect(setting)}"}
    end
  end

  def sql(column, digits) when digits in [0, 3] do
    at =
      "(LEAST(#{column}, make_timestamp(#{Date.utc_today().year + 100}, 12, 31, 23, 59, 59)) AT TIME ZONE 'UTC')"

    fraction = if digits == 3, do: ".MS", else: ""

    "CASE WHEN #{column} IS NULL THEN NULL ELSE " <>
      "to_char(#{column} + make_interval(secs => extract(timezone FROM #{at})::double precision), " <>
      "'YYYY-MM-DD\"T\"HH24:MI:SS#{fraction}') || " <>
      "CASE WHEN to_char(#{at}, 'TZ') IN ('UTC', 'UCT') THEN 'Z' ELSE to_char(#{at}, 'TZH:TZM') END END"
  end

  defp set_zone(repo, zone) do
    case repo.query("SELECT set_config('TimeZone', $1, true)", [zone]) do
      {:ok, %{rows: [[^zone]]}} -> :ok
      {:ok, _} -> {:replay, "time zone #{zone} is not PostgreSQL's canonical spelling"}
      {:error, %Postgrex.Error{}} -> {:replay, "PostgreSQL does not know time zone #{zone}"}
    end
  end
end
