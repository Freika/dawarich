defmodule Dawarich.Test.NormalWholeEffects do
  @moduledoc false
  import ExUnit.Assertions

  def record_order!(repo) do
    repo.query!("CREATE SEQUENCE phoenix.normal_enqueue_order", [], log: false)

    for table <- ~w(job_outbox phoenix.rails_commands) do
      repo.query!(
        "ALTER TABLE #{table} ADD COLUMN test_enqueue_order bigint NOT NULL DEFAULT nextval('phoenix.normal_enqueue_order')",
        [],
        log: false
      )
    end
  end

  def remove_order!(repo) do
    for table <- ~w(job_outbox phoenix.rails_commands) do
      repo.query!("ALTER TABLE #{table} DROP COLUMN test_enqueue_order", [], log: false)
    end

    repo.query!("DROP SEQUENCE phoenix.normal_enqueue_order", [], log: false)
  end

  def expected(c, _owner) do
    assert c.expected["jobs"] ==
             for(
               %{"kind" => "rails.job", "payload" => job} <- c.expected["ordered_effects"],
               do: job
             )

    assert c.expected["commands"] ==
             Enum.reject(c.expected["ordered_effects"], &(&1["kind"] == "rails.job"))

    {effects, []} =
      Enum.reduce(c.expected["ordered_effects"], {[], []}, fn
        %{
          "kind" => "rails.job",
          "payload" => %{"type" => "Stats::CalculatingJob", "args" => [user, year, month]}
        },
        {effects, months} ->
          assert user == c.import.user_id
          {effects, months ++ [[year, month]]}

        %{
          "kind" => "rails.job",
          "payload" => %{"type" => "Achievements::CheckJob", "args" => [user]}
        },
        {effects, months} ->
          assert user == c.import.user_id
          oldest = c.expected["points"] |> Enum.map(& &1["timestamp"]) |> Enum.min(fn -> nil end)

          effect =
            reverse(c, "schedule_stats", %{"months" => months, "oldest_timestamp" => oldest})

          {[effect | effects], []}

        %{"kind" => "rails.job", "payload" => job}, {effects, months} ->
          {[job(c, job) | effects], months}

        %{"kind" => kind, "payload" => payload}, {effects, months} ->
          payload = Map.put(payload, "user_id", c.import.user_id)

          payload =
            if kind == "imports.progress",
              do: Map.put(payload, "import_id", c.import.id),
              else: payload

          {[[kind, payload] | effects], months}
      end)

    effects
    |> Enum.reverse()
    |> Enum.reject(fn [kind, _] -> kind == "imports.progress" end)
  end

  def assert_routes(c, repo, owner) do
    commands =
      for ["command", payload] <- expected(c, owner), do: payload

    native =
      Enum.filter(commands, fn command ->
        command["command_type"] == "imports.process_normal" or owner == :oban
      end)

    reverse_commands = commands -- native

    rows =
      repo.query!(
        "SELECT payload FROM phoenix.rails_commands WHERE kind='imports.postprocessing_step' AND payload->>'step'='command' ORDER BY id",
        [],
        log: false
      ).rows
      |> List.flatten()

    assert rows ==
             Enum.map(reverse_commands, fn command ->
               Map.merge(
                 base(c, "command"),
                 Map.put(command, "aggregate_id", aggregate(c, command))
               )
             end)

    {microseconds, _} = c.context.now.microsecond
    scheduled = %{c.context.now | microsecond: {microseconds, 6}}

    rows =
      repo.query!(
        "SELECT command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at,state FROM job_outbox ORDER BY test_enqueue_order",
        [],
        log: false
      ).rows

    assert rows ==
             Enum.map(native, fn command ->
               type = command["command_type"]
               id = command["command_payload"]["import_id"]

               [
                 type,
                 1,
                 command["command_payload"],
                 %{"producer" => "Phoenix Imports Postprocessing"},
                 aggregate(c, command),
                 if(type == "imports.update_points_count", do: "points-count:#{id}"),
                 scheduled,
                 "pending"
               ]
             end)
  end

  defp aggregate(c, %{"command_type" => "tracks.generate_range"}), do: c.import.user_id
  defp aggregate(_c, command), do: command["command_payload"]["import_id"]

  defp job(c, %{"type" => "VisitSuggestingJob", "args" => [args]}) do
    args = decode(args)
    assert args["user_id"] == c.import.user_id
    reverse(c, "schedule_visit_suggesting", Map.take(args, ["start_at", "end_at"]))
  end

  defp job(c, %{"type" => "Tracks::ParallelGeneratorJob", "args" => [user, args]}) do
    assert user == c.import.user_id

    payload =
      args
      |> decode()
      |> Map.merge(%{
        "user_id" => user,
        "time_zone" => c.expected["zone"],
        "low_priority" => false
      })

    command("tracks.generate_range", payload)
  end

  defp job(_c, %{"type" => "Import::UpdatePointsCountJob", "args" => [id]}),
    do: command("imports.update_points_count", %{"import_id" => id})

  defp job(c, %{"type" => "Import::ProcessJob", "args" => [id]}),
    do:
      command(
        "imports.process_normal",
        %{"import_id" => id, "user_id" => c.import.user_id, "time_zone" => c.expected["zone"]}
      )

  defp job(c, %{"type" => "EnhancedImport::ExtractJob", "args" => [id]}) do
    assert id == c.import.id
    reverse(c, "extract", %{})
  end

  defp job(c, %{"type" => "ActiveStorage::PurgeJob", "args" => [%{"_aj_globalid" => gid}]}) do
    blob = gid |> String.split("/") |> List.last() |> String.to_integer()

    [
      "imports.prepared_download_purge",
      %{
        "blob_id" => blob,
        "source_blob_id" => blob,
        "user_id" => c.import.user_id,
        "import_id" => c.import.id
      }
    ]
  end

  defp reverse(c, step, extra),
    do: ["imports.postprocessing_step", Map.merge(base(c, step), extra)]

  defp base(c, step),
    do: %{
      "user_id" => c.import.user_id,
      "import_id" => c.import.id,
      "locale" => c.expected["locale"],
      "time_zone" => c.expected["zone"],
      "step" => step
    }

  defp command(type, payload),
    do: ["command", %{"command_type" => type, "command_payload" => payload}]

  defp decode(%{
         "_aj_serialized" => "ActiveJob::Serializers::TimeWithZoneSerializer",
         "value" => value
       }) do
    {:ok, time, _} = DateTime.from_iso8601(value)
    time |> DateTime.to_unix() |> DateTime.from_unix!() |> DateTime.to_iso8601()
  end

  defp decode(%{"_aj_serialized" => "ActiveJob::Serializers::SymbolSerializer", "value" => value}),
    do: value

  defp decode(map) when is_map(map),
    do:
      Map.new(
        map
        |> Map.drop(["_aj_ruby2_keywords"])
        |> Enum.map(fn {key, value} -> {key, decode(value)} end)
      )

  defp decode(value), do: value
end
