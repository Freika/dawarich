defmodule Dawarich.Visits.BulkSweepWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Visits.{BulkSweep, BulkSweepWorker}

  @oban __MODULE__.Oban
  @fixture Path.expand("../../fixtures/a12d3/schedules.json", __DIR__)
  @profiles ~w(cron_defaults explicit singular union disabled selection berlin_dst berlin_fall tokyo utc year_chunks future string_bounds)

  setup do
    start_oban(@oban)
    :ok
  end

  test "bulk visit sweep matches Rails eligibility and previous-day chunks across DST" do
    cases = Jason.decode!(File.read!(@fixture))["classes"]["BulkVisitsSuggestingJob"]["cases"]

    for profile <- @profiles do
      reset!(ScratchRepo)
      f = Enum.find(cases, &(&1["id"] == profile))
      load_users(f["users"])
      Ownership.put!(ScratchRepo, "command:visits.suggest", :oban)
      Ownership.put!(ScratchRepo, BulkSweepWorker.key(), :oban)
      {:ok, now, _offset} = DateTime.from_iso8601(f["now"])
      opts = [env: env(profile), now: now]

      result =
        if f["input"] == %{} do
          BulkSweepWorker.run_cron(
            ScratchRepo,
            @oban,
            DateTime.to_unix(now),
            opts ++ [time_zone: f["ambient_zone"]]
          )
        else
          {start, stop} = explicit_bounds(f)

          args = %{
            "start_at" => start,
            "end_at" => stop,
            "user_ids" => selectors(f),
            "time_zone" => f["ambient_zone"],
            "event_id" => Ecto.UUID.generate()
          }

          args = Map.put(args, "source_job_id", args["event_id"])

          assert {:ok, decoded} =
                   BulkSweepWorker.args_from_command(1, Map.delete(args, "event_id"))

          BulkSweepWorker.run(ScratchRepo, @oban, Map.merge(decoded, args), opts)
        end

      assert result == :ok

      jobs =
        rows(
          "SELECT args FROM oban.oban_jobs WHERE worker = 'Dawarich.Visits.SuggestWorker' ORDER BY id"
        )

      actual = Enum.map(jobs, fn [args] -> Map.take(args, ~w(user_id start_at end_at)) end)

      expected =
        Enum.map(f["jobs"], fn job ->
          [args] = job["arguments"]

          %{
            "user_id" => args["user_id"],
            "start_at" => epoch(args["start_at"]),
            "end_at" => epoch(args["end_at"])
          }
        end)

      assert Enum.sort(actual) == Enum.sort(expected), profile

      for [args] <- jobs do
        assert args["stepping"] == "fixed"
        assert args["time_zone"] == "Asia/Tokyo"
        assert args["cursor"] == args["start_at"]
        user = Enum.find(f["users"], &(&1["id"] == args["user_id"]))
        assert args["plan_restricted"] == (user["plan"] == "lite")
      end

      if f["input"] == %{} do
        assert BulkSweepWorker.run_cron(
                 ScratchRepo,
                 @oban,
                 DateTime.to_unix(now),
                 opts ++ [time_zone: f["ambient_zone"]]
               ) == :ok

        assert rows(
                 "SELECT args FROM oban.oban_jobs WHERE worker = 'Dawarich.Visits.SuggestWorker' ORDER BY id"
               ) == jobs
      end
    end

    reset!(ScratchRepo)

    rows(
      "INSERT INTO users (id, email, settings, status, plan, points_count, created_at, updated_at) " <>
        "SELECT g, 'bulk-' || g || '@example.invalid', '{}', 1, 1, 1, now(), now() FROM generate_series(52001,53001) g"
    )

    Ownership.put!(ScratchRepo, "command:visits.suggest", :oban)

    args = %{
      "event_id" => BulkSweep.cron_id(1_759_660_800),
      "start_at" => "2025-10-04T00:00:00Z",
      "end_at" => "2025-10-04T23:59:59Z",
      "user_ids" => [],
      "time_zone" => "Etc/UTC"
    }

    assert BulkSweepWorker.run(ScratchRepo, @oban, args, env: env("selection")) == :ok

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker = 'Dawarich.Visits.SuggestWorker'"
           ) == [[1000]]

    assert [[next]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker = 'Dawarich.Visits.BulkSweepWorker'"
             )

    assert next["after_id"] == 53000
    assert Map.take(next, Map.keys(args)) == args
    assert BulkSweepWorker.run(ScratchRepo, @oban, next, env: env("selection")) == :ok

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker = 'Dawarich.Visits.SuggestWorker'"
           ) == [[1001]]

    reset!(ScratchRepo)
    f = Enum.find(cases, &(&1["id"] == "cron_defaults"))
    load_users(f["users"])
    Ownership.put!(ScratchRepo, BulkSweepWorker.key(), :oban)
    {:ok, now, _} = DateTime.from_iso8601(f["now"])

    assert BulkSweepWorker.run_cron(ScratchRepo, @oban, DateTime.to_unix(now),
             env: env("cron_defaults"),
             time_zone: f["ambient_zone"],
             now: now
           ) == :ok

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    intents = rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id")
    assert length(intents) == length(f["jobs"])

    for [kind, payload] <- intents do
      assert kind == "visits.suggest"

      assert Map.keys(payload) |> Enum.sort() ==
               ~w(end_at event_id plan_restricted start_at stepping time_zone user_id)

      assert payload["stepping"] == "fixed"
      assert payload["time_zone"] == "Asia/Tokyo"
    end
  end

  test "accepted bulk work completes natively after pinned release and retains source identity" do
    f =
      Jason.decode!(File.read!(@fixture))["classes"]["BulkVisitsSuggestingJob"]["cases"]
      |> Enum.find(&(&1["id"] == "cron_defaults"))

    load_users(f["users"])
    root = Ecto.UUID.generate()
    {start, stop} = explicit_bounds(f)

    args = %{
      "event_id" => root,
      "source_job_id" => root,
      "start_at" => start,
      "end_at" => stop,
      "user_ids" => [],
      "time_zone" => f["ambient_zone"]
    }

    accepted = Oban.insert!(@oban, BulkSweepWorker.new(args))

    for key <- ["command:visits.bulk_suggest", BulkSweepWorker.key(), "command:visits.suggest"] do
      Ownership.put!(ScratchRepo, key, :sidekiq, pinned: true)
    end

    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    saved = Map.new(~w(SELF_HOSTED PHOTON_API_HOST), &{&1, System.get_env(&1)})
    System.put_env(env("cron_defaults"))

    on_exit(fn ->
      Application.put_env(:dawarich, :jobs_repo, previous)

      Enum.each(saved, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(@oban, queue: :visit_suggesting, with_limit: 1)

    assert rows("SELECT state FROM oban.oban_jobs WHERE id = $1", [accepted.id]) == [
             ["completed"]
           ]

    assert rows("SELECT handler FROM phoenix.processed_commands WHERE event_id = $1", [
             Ecto.UUID.dump!(root)
           ]) == [["visits.bulk_suggest"]]

    assert length(rows("SELECT kind FROM phoenix.rails_commands WHERE kind = 'visits.suggest'")) ==
             length(f["jobs"])

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker = 'Dawarich.Visits.SuggestWorker'"
           ) == [[0]]

    assert BulkSweepWorker.run(ScratchRepo, @oban, args, env: env("cron_defaults")) == :ok

    assert length(rows("SELECT kind FROM phoenix.rails_commands WHERE kind = 'visits.suggest'")) ==
             length(f["jobs"])
  end

  defp load_users(users) do
    for user <- users do
      rows(
        "INSERT INTO users (id,email,settings,status,plan,points_count,deleted_at,created_at,updated_at) " <>
          "VALUES ($1,$2,$3,$4,$5,$6,$7,now(),now())",
        [
          user["id"],
          "bulk-#{user["id"]}@example.invalid",
          %{
            "timezone" => "Asia/Tokyo",
            "visits_suggestions_enabled" => if(user["suggestions"], do: "true", else: "false")
          },
          %{"inactive" => 0, "active" => 1, "trial" => 2}[user["status"]],
          %{"lite" => 0, "pro" => 1, "family" => 2}[user["plan"]],
          user["points_count"],
          if(user["deleted"], do: ~N[2026-10-04 12:00:00], else: nil)
        ]
      )
    end
  end

  defp env("disabled"), do: %{"SELF_HOSTED" => "false"}

  defp env(_profile),
    do: %{"SELF_HOSTED" => "false", "PHOTON_API_HOST" => "photon.example.invalid"}

  defp epoch(iso), do: iso |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_unix()

  defp explicit_bounds(f) do
    [bounds] = f["time_chunks_calls"]
    {bounds["start_at"]["value"], bounds["end_at"]["value"]}
  end

  defp selectors(f),
    do:
      Enum.uniq(
        Enum.reject(
          List.wrap(f["input"]["user_ids"]) ++ List.wrap(f["input"]["user_id"]),
          &is_nil/1
        )
      )
end
