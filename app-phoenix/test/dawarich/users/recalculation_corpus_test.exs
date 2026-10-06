defmodule Dawarich.Users.RecalculationCorpusTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: F
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Points.AnomalyBackfillWorker
  alias Dawarich.ReleaseOperations, as: Ops
  alias Dawarich.ReleaseOperations.{Anomalies, AnomaliesUser, AnomalyClaims, PerTracker}
  alias Dawarich.State
  alias Dawarich.Stats.{CalculateMonth, FullRecalculation}
  alias Dawarich.Users.{RecalculateWorker, RecalculationArgs, RecalculationPeriod}

  @now ~U[2026-10-03 12:00:00Z]
  @source Path.expand("../../fixtures/a12d1b3/Records.json", __DIR__)

  setup do
    pool =
      start_supervised!({ScratchRepo, [name: nil, pool_size: 2, parameters: [timezone: "UTC"]]},
        id: :corpus_utc
      )

    ScratchRepo.put_dynamic_repo(pool)
    on_exit(fn -> ScratchRepo.put_dynamic_repo(ScratchRepo) end)
    start_oban(__MODULE__)
    :ok
  end

  @cases F.all()
  55 = length(@cases)

  for source <- @cases do
    @source_case source
    test "matches source recalculation through real workers: #{source["id"]}" do
      source = @source_case
      F.load!(ScratchRepo, source)
      name = source["id"]
      Process.put(:corpus_case, name)
      Process.put(:corpus_replayed, false)
      opts = options(source)

      case source["job"]["job_class"] do
        "Stats::FullRecalculationJob" -> full(source)
        "Users::RecalculateDataJob" -> user(source, opts)
        "Points::AnomalyBackfillUserJob" -> backfill(source, opts)
        "DataMigrations::RecalculateAnomaliesUserJob" -> fleet(source, opts)
        "DataMigrations::RecalculateAnomaliesJob" -> dispatch(source, opts)
        "DataMigrations::RecalculatePerTrackerTracksJob" -> tracker(source, opts)
      end

      assert_fields(source)
      assert_calls(source)
      assert_notifications(source)

      assert rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'mail.%' OR kind LIKE 'digests.email_%'"
             ) == [[0]],
             name

      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker LIKE '%Digests%'") == [[0]],
             name
    end
  end

  test "recalculation routes retain explicit hand-backs and expose native digest generation" do
    for path <- ["/api/v1/recalculations", "/tracks/recalculation"] do
      assert Phoenix.Router.route_info(DawarichWeb.Router, "POST", path, "localhost") == :error
    end

    assert %{plug: DawarichWeb.DigestActions, plug_opts: :create} =
             Phoenix.Router.route_info(DawarichWeb.Router, "POST", "/digests", "localhost")

    original = Application.get_env(:dawarich, :rails_routes)
    Application.put_env(:dawarich, :rails_routes, ["digests", "api"])
    assert DawarichWeb.Strangler.handed_back?(["digests", "2025"])
    assert DawarichWeb.Strangler.handed_back?(["api", "v1", "stats"])
    Application.put_env(:dawarich, :rails_routes, original)
  end

  test "a lost composite lease prevents the calculator from committing stats or failure notices" do
    source = F.case!("user_specific")
    F.load!(ScratchRepo, source)

    args =
      common(source)
      |> Map.merge(%{"user_id" => 170_101, "year" => 2025, "notify" => true, "job_queue" => nil})

    steal = fn repo, id, year, month, opts ->
      rows(
        "UPDATE phoenix.leases SET holder='replacement' WHERE name=$1",
        ["users.recalculate_data:" <> args["event_id"]]
      )

      CalculateMonth.call(repo, id, year, month, opts)
    end

    assert {:error, %RuntimeError{message: "recalculation lease lost"}} =
             RecalculateWorker.run(ScratchRepo, __MODULE__, args,
               now: @now,
               env: %{"SELF_HOSTED" => "false"},
               stats: steal
             )

    assert rows("SELECT count(*) FROM stats") == [[0]]
    assert rows("SELECT count(*) FROM notifications") == [[0]]
    assert rows("SELECT count(*) FROM digests") == [[0]]

    assert lease_holders(ScratchRepo, "users.recalculate_data:" <> args["event_id"]) == [
             ["replacement"]
           ]
  end

  defp options(source) do
    parent = self()
    name = source["id"]

    before_month = fn year, month, state ->
      send(parent, {:call, {:stats, year, month, state.locale, zone(state.zone)}})
      if name == "user_stats_escape", do: failure()

      if name == "user_nested_argument" and month == 2 and not Process.get(:corpus_replayed) do
        Process.put(:corpus_replayed, true)
        raise ArgumentError, "synthetic nested argument"
      end
    end

    phase = fn kind, year, state ->
      send(parent, {:call, {kind, year, state.locale, zone(state.zone)}})
      if name == "user_digest_escape" and kind == :digest, do: failure()
      if String.starts_with?(name, "fleet_rebuild") and kind == :tracks, do: failure()
    end

    opts = [
      now: @now,
      env: %{"SELF_HOSTED" => "false"},
      jitter_draw: 0,
      lease: [timeout_ms: 0],
      range_opts: [lock: [timeout_ms: 0]],
      before_month: before_month,
      phase: phase,
      after_month: fn first ->
        [[last]] =
          rows("SELECT extract(epoch FROM (to_timestamp($1) + interval '1 month'))::bigint", [
            first
          ])

        send(parent, {:call, {:filter, first, last}})

        if String.ends_with?(name, "interrupted") and first == 1_735_689_600,
          do: :interrupted,
          else: :ok
      end
    ]

    if name == "user_stats_handled" do
      Keyword.put(opts, :stats, fn repo, id, _, _, options ->
        CalculateMonth.call(
          repo,
          id,
          2025,
          3,
          Keyword.put(options, :hexagons, fn _, _, _, _ -> failure() end)
        )
      end)
    else
      opts
    end
  end

  defp full(source) do
    args = common(source) |> Map.put("user_id", 170_101)
    Ownership.put!(ScratchRepo, "command:stats.calculate_month", :sidekiq)
    State.debounce(ScratchRepo, "stats_full_recalculation:user:170101", 300)
    assert FullRecalculation.run(ScratchRepo, args, oban: __MODULE__) == :ok, source["id"]

    actual =
      rows(
        "SELECT payload->'year',payload->'month',payload->'notify_on_failure' FROM phoenix.rails_commands ORDER BY id"
      )

    expected =
      for job <- source["expected"]["jobs"],
          do: [Enum.at(job["arguments"], 1), Enum.at(job["arguments"], 2), true]

    expected =
      if source["id"] == "full_stale",
        do: List.insert_at(expected, 2, [2025, 6, true]),
        else: expected

    assert actual == expected, source["id"]
    refute State.claimed?(ScratchRepo, "stats_full_recalculation:user:170101")
  end

  defp user(source, opts) do
    [id, params] = source["job"]["arguments"]

    args =
      common(source)
      |> Map.merge(%{
        "user_id" => id,
        "year" => params["year"],
        "notify" => params["notify"],
        "job_queue" => params["job_queue"]
      })

    name = source["id"]

    if name == "user_invalid_year" do
      assert RecalculationPeriod.years(ScratchRepo, id, params["year"]) == {:error, :invalid_year}

      assert RecalculationArgs.decode("users.recalculate_data", 1, Map.delete(args, "event_id")) ==
               {:error, "invalid_payload"}
    else
      if String.contains?(name, "busy") do
        hold_lease!(ScratchRepo, "tracks:per_user_lock:170101", "source-busy")

        if name != "user_busy",
          do:
            State.put_cursor(ScratchRepo, "users.recalculate_data:busy:" <> args["event_id"], "4")
      end

      result = RecalculateWorker.run(ScratchRepo, __MODULE__, args, opts)

      cond do
        name == "user_busy" ->
          assert result == {:snooze, 3}, name

        name in ~w(user_stats_escape user_digest_escape) ->
          assert {:error, %RuntimeError{message: "synthetic recalculation failure"}} = result

        true ->
          assert result == :ok, "#{name}: #{inspect(result)}"
      end
    end
  end

  defp backfill(source, opts) do
    [id, params] = source["job"]["arguments"]

    args =
      common(source)
      |> Map.merge(Map.take(params, ~w(reset notify rebuild)))
      |> Map.merge(%{"user_id" => id, "rebuild" => params["rebuild"]["value"], "progress" => %{}})

    if source["id"] == "backfill_busy",
      do: hold_lease!(ScratchRepo, "anomaly_backfill:170101", "source-busy")

    opts = backfill_options(opts)
    result = AnomalyBackfillWorker.run(ScratchRepo, __MODULE__, args, opts)

    expected =
      if source["id"] == "backfill_interrupted",
        do: {:ok, nil},
        else: {:ok, source["expected"]["result"]}

    assert result == expected, source["id"]

    if source["id"] == "backfill_async" do
      assert rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE kind='users.recalculate_data'"
             ) == [[1]]
    end
  end

  defp fleet(source, opts) do
    [id, params] = source["job"]["arguments"]

    request =
      common(source)
      |> Map.delete("event_id")
      |> Map.merge(%{"user_id" => id, "attempt" => params["attempt"]})

    {:ok, args} = AnomaliesUser.args_from_command(1, request)
    args = Map.put(args, "event_id", request["source_job_id"])

    args =
      if source["id"] == "fleet_rebuild_exhausted",
        do: put_in(args, ["cursor", "rebuild_attempt"], 3),
        else: args

    if String.contains?(source["id"], "busy"),
      do: hold_lease!(ScratchRepo, "anomaly_backfill:170101", "source-busy")

    assert operation(AnomaliesUser, args, backfill_options(opts)) == :ok, source["id"]

    expected =
      Enum.count(
        source["expected"]["jobs"],
        &(&1["job_class"] == "DataMigrations::RecalculateAnomaliesJob")
      )

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.ReleaseOperations.Anomalies'"
           ) == [[expected]],
           source["id"]
  end

  defp dispatch(source, opts) do
    request = common(source) |> Map.delete("event_id") |> Map.put("limit", 2)
    {:ok, args} = Anomalies.args_from_command(1, request)
    args = Map.put(args, "event_id", request["source_job_id"])

    if source["id"] == "dispatch_malformed" do
      assert_raise Postgrex.Error, fn -> operation(Anomalies, args, opts) end
    else
      expected = Enum.find(source["expected"]["calls"], &(&1["kind"] == "pending"))
      assert AnomalyClaims.pending_ids(ScratchRepo, @now) == expected["user_ids"], source["id"]
      assert operation(Anomalies, args, opts) == :ok, source["id"]

      actual =
        rows(
          "SELECT (args->'cursor'->'request'->>'user_id')::int FROM oban.oban_jobs ORDER BY id"
        )
        |> List.flatten()

      expected = Enum.map(source["expected"]["jobs"], &hd(&1["arguments"]))
      assert actual == expected, source["id"]
    end
  end

  defp tracker(source, opts) do
    id = List.first(source["job"]["arguments"])
    request = common(source) |> Map.delete("event_id") |> Map.put("user_id", id)
    {:ok, args} = PerTracker.args_from_command(1, request)
    args = Map.put(args, "event_id", request["source_job_id"])
    dir = Path.join(System.tmp_dir!(), "corpus-records-#{Ecto.UUID.generate()}")
    storage = Path.join(dir, "storage")
    path = Path.join([storage, "a1", "2d", "a12d1b3-records-source"])
    File.mkdir_p!(Path.dirname(path))
    File.mkdir_p!(Path.join(dir, "tmp"))

    if source["id"] == "tracker_corrupt",
      do: File.write!(path, "{broken"),
      else: File.cp!(@source, path)

    opts =
      opts
      |> Keyword.put(:services, %{
        "test" => %{service: "local", stored_service: "test", root: storage}
      })
      |> Keyword.put(:download_opts, temp_dir: Path.join(dir, "tmp"))
      |> Keyword.put(:rand, fn 0..3600 ->
        if source["id"] == "tracker_stagger_zero", do: 0, else: 3600
      end)
      |> Keyword.put(:after_repair, fn devices, raw ->
        send(self(), {:call, {:records, 170_801, devices}})
        send(self(), {:call, {:raw, 170_101, raw}})

        if source["id"] == "tracker_retry" and not Process.get(:corpus_replayed) do
          Process.put(:corpus_replayed, true)
          raise "synthetic rebuild contention"
        end
      end)

    try do
      if source["id"] == "tracker_retry" do
        assert_raise RuntimeError, "synthetic rebuild contention", fn ->
          operation(PerTracker, args, opts)
        end
      end

      assert operation(PerTracker, args, opts) == :ok, source["id"]
      assert File.ls!(Path.join(dir, "tmp")) == []

      if id == nil do
        [[child, due]] = rows("SELECT args,scheduled_at FROM oban.oban_jobs")
        assert child["cursor"]["request"]["user_id"] == 170_101
        [expected] = source["expected"]["jobs"]
        {:ok, at, _} = DateTime.from_iso8601(expected["scheduled_at"])
        assert DateTime.to_unix(DateTime.from_naive!(due, "Etc/UTC")) == DateTime.to_unix(at)
      end
    after
      File.rm_rf!(dir)
    end
  end

  defp backfill_options(opts) do
    parent = self()

    opts
    |> Keyword.delete(:before_month)
    |> Keyword.put(:stats, fn repo, id, year, month, options ->
      [[settings]] = rows("SELECT settings FROM users WHERE id=$1", [id])
      locale = Dawarich.Mail.ExploreFeatures.locale(settings, nil)
      at = RecalculationPeriod.zone(repo, settings, %{})
      send(parent, {:call, {:stats, year, month, locale, zone(at)}})
      CalculateMonth.call(repo, id, year, month, options)
    end)
  end

  defp operation(worker, args, opts),
    do:
      Ops.run(
        ScratchRepo,
        __MODULE__,
        worker,
        %Oban.Job{args: args, attempt: 1, max_attempts: 26},
        opts
      )

  defp common(source),
    do: %{
      "source_job_id" => source["job"]["job_id"],
      "event_id" => source["job"]["job_id"],
      "ambient_zone" => source["job"]["timezone"]
    }

  defp assert_fields(source) do
    for {table, fields} <- [
          {"stats",
           ~w(user_id year month distance daily_distance flight_distance toponyms h3_hex_ids calculation_version)},
          {"digests", nil},
          {"points",
           ~w(id user_id import_id timestamp tracker_id track_id anomaly raw_data velocity)},
          {"users", ~w(id settings deleted_at)}
        ] do
      expected = source["expected"]["rows"][table]

      fields =
        fields ||
          (List.first(expected) || %{})
          |> Map.keys()
          |> Enum.reject(&(&1 in ~w(id sharing_uuid created_at updated_at)))

      if fields != [] do
        actual =
          rows(
            "SELECT row_to_json(t)::text FROM (SELECT #{Enum.join(fields, ",")} FROM #{table} ORDER BY id) t"
          )
          |> Enum.map(fn [value] -> Jason.decode!(value) end)

        expected = Enum.map(expected, &Map.take(&1, fields))
        sorter = fn row -> {row["user_id"], row["year"], row["month"], row["id"]} end

        assert Enum.sort_by(actual, sorter) == Enum.sort_by(expected, sorter),
               "#{source["id"]}/#{table}"
      else
        assert rows("SELECT count(*) FROM #{table}") == [[0]], "#{source["id"]}/#{table}"
      end
    end
  end

  defp assert_calls(source) do
    expected =
      for call <- source["expected"]["calls"],
          call["kind"] in ~w(stats tracks digest filter records raw) do
        case call["kind"] do
          "stats" ->
            {:stats, Enum.at(call["args"], 1), Enum.at(call["args"], 2), call["locale"],
             zone(call["zone"])}

          "digest" ->
            {:digest, Enum.at(call["args"], 1), call["locale"], zone(call["zone"])}

          "tracks" ->
            {:tracks, String.to_integer(String.slice(call["options"]["start_at"], 0, 4)),
             call["locale"], zone(call["zone"])}

          "filter" ->
            {:filter, Enum.at(call["args"], 1), Enum.at(call["args"], 2)}

          "records" ->
            {:records, call["import_id"], call["result"]}

          "raw" ->
            {:raw, call["user_id"], call["result"]}
        end
      end

    actual = calls()
    assert actual == expected, "#{source["id"]}/calls: #{inspect({actual, expected})}"
  end

  defp assert_notifications(source) do
    actual =
      rows("SELECT kind,title,content FROM notifications ORDER BY id")
      |> Enum.map(fn [kind, title, content] ->
        [Dawarich.Notifications.kind_name(kind), title, content]
      end)

    expected = source["expected"]["notifications"]

    if source["id"] in ~w(user_stats_handled user_stats_escape user_digest_escape) do
      assert Enum.map(actual, &Enum.take(&1, 2)) == Enum.map(expected, &Enum.take(&1, 2)),
             source["id"]

      for [kind, _, body] <- actual,
          kind == "error",
          do: assert(body =~ "synthetic recalculation failure", source["id"])

      for notice <- actual, hd(notice) != "error", do: assert(notice in expected, source["id"])
    else
      assert actual == expected, "#{source["id"]}/notices"
    end
  end

  defp calls do
    receive do
      {:call, call} -> [call | calls()]
    after
      0 -> []
    end
  end

  defp zone(name) when name in ["UTC", "Etc/UTC"], do: "Etc/UTC"
  defp zone(name), do: name
  defp failure, do: raise("synthetic recalculation failure")
end
