defmodule Dawarich.Digests.ExecutionUpgrade do
  @moduledoc false

  alias Dawarich.Digests.{Execution, Generation}
  alias Dawarich.Stats.EffectIdentity

  def backfill(repo) do
    if readable?(repo, "public.digests") and readable?(repo, "phoenix.rails_commands") do
      path =
        Application.app_dir(
          :dawarich,
          "priv/repo/sql/20261007180000_digest_executions_backfill.sql"
        )

      repo.query!(File.read!(path), [], log: false)
    end

    sources = [
      {"oban.oban_jobs", "id", 0, "args", fn args, _ -> args end},
      {"public.job_outbox", "event_id::text", "", "payload,event_id::text",
       fn args, event -> Map.put(args, "event_id", event) end},
      {"phoenix.rails_commands", "id", 0, "payload",
       fn args, _ -> Map.put(args, "event_id", args["source_job_id"]) end}
    ]

    for {table, key, cursor, fields, build} <- sources do
      if readable?(repo, table),
        do: scan(repo, table, key, fields, build, cursor)
    end

    :ok
  end

  defp readable?(repo, table) do
    [schema, _] = String.split(table, ".")

    repo.query!(
      "SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname=$1 AND has_schema_privilege(oid,'USAGE'))",
      [schema],
      log: false
    ).rows == [[true]] and
      repo.query!("SELECT to_regclass($1) IS NOT NULL", [table], log: false).rows == [[true]] and
      repo.query!("SELECT has_table_privilege($1,'SELECT')", [table], log: false).rows == [[true]]
  end

  defp scan(repo, table, key, fields, build, cursor) do
    rows =
      repo.query!(
        "SELECT #{key},#{fields} FROM #{table} WHERE #{key}>$1 ORDER BY #{key} LIMIT 500",
        [cursor],
        log: false
      ).rows

    for [_, args | rest] <- rows,
        is_map(args),
        args["event_id"] || rest != [] || args["source_job_id"],
        do: adopt_candidate(repo, build.(args, List.first(rest)))

    case List.last(rows) do
      nil -> :ok
      [id | _] -> scan(repo, table, key, fields, build, id)
    end
  end

  defp adopt_candidate(repo, %{"user_id" => user, "year" => year, "event_id" => event} = args)
       when is_integer(user) and is_integer(year) and is_binary(event) do
    kind = if is_integer(args["month"]) and args["month"] in 1..12, do: :monthly, else: :yearly
    [handler | _] = key = Execution.key(kind, args)
    generation = String.replace(handler, "calculate_", "generate_")
    old = EffectIdentity.id(event, generation, args)
    terminal = Generation.receipt(kind, args)
    shared = EffectIdentity.id(terminal, generation, %{})

    ids =
      [old, terminal, shared] ++ if(Ecto.UUID.cast(event) == {:ok, event}, do: [event], else: [])

    markers =
      repo.query!(
        "SELECT event_id::text,handler FROM phoenix.processed_commands WHERE event_id=ANY($1::uuid[])",
        [Enum.map(ids, &Ecto.UUID.dump!/1)],
        log: false
      ).rows
      |> Map.new(fn [id, value] -> {id, value} end)

    if markers[old] == generation <> ":failed" do
      repo.query!(
        "DELETE FROM phoenix.processed_commands WHERE event_id=$1 AND handler=$2",
        [Ecto.UUID.dump!(terminal), handler],
        log: false
      )
    end

    state =
      cond do
        markers[old] == generation <> ":failed" ->
          nil

        markers[terminal] == handler or markers[event] == handler ->
          {"published", "mail"}

        markers[shared] in [generation <> ":mail", generation <> ":missing"] ->
          {"generated", String.replace_prefix(markers[shared], generation <> ":", "")}

        markers[old] in [generation <> ":mail", generation <> ":missing"] ->
          {"generated", String.replace_prefix(markers[old], generation <> ":", "")}

        true ->
          nil
      end

    if state do
      {status, outcome} = state

      repo.query!(
        "INSERT INTO phoenix.digest_executions(effect,user_id,year,month,state,outcome,legacy) VALUES($1,$2,$3,$4,$5,$6,true) " <>
          "ON CONFLICT(effect,user_id,year,month) DO UPDATE SET state=EXCLUDED.state,outcome=EXCLUDED.outcome " <>
          "WHERE digest_executions.legacy AND digest_executions.state<>'published'",
        key ++ [status, outcome],
        log: false
      )
    end
  end

  defp adopt_candidate(_repo, _args), do: :ok
end
