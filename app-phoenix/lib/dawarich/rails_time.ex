defmodule Dawarich.RailsTime do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.TimeZoneName

  @context_key {__MODULE__, :zone_context}

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
        case in_zone(repo, zone, fun) do
          {:ok, result} -> result
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

  defp in_zone(repo, zone, fun) do
    # Query/transaction adapters need not expose an Ecto dynamic repository.
    # Only optimize a context whose repository identity we can establish.
    if function_exported?(repo, :get_dynamic_repo, 0) do
      scoped_zone(repo, zone, fun)
    else
      Process.delete(@context_key)

      try do
        case set_zone(repo, zone) do
          :ok -> {:ok, fun.()}
          replay -> replay
        end
      after
        Process.delete(@context_key)
      end
    end
  end

  defp scoped_zone(repo, zone, fun) do
    context = {repo, repo.get_dynamic_repo(), zone}
    previous = Process.get(@context_key)
    result = if previous == context, do: :ok, else: set_zone(repo, zone)

    case result do
      :ok ->
        Process.put(@context_key, context)

        try do
          {:ok, fun.()}
        after
          # A different nested zone changes PostgreSQL's transaction-local state.
          # Invalidate the outer marker so its next use sets the zone again.
          if previous == context and Process.get(@context_key) == context,
            do: Process.put(@context_key, previous),
            else: Process.delete(@context_key)
        end

      replay ->
        replay
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
