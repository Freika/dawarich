defmodule Dawarich.A12f3bC02Test do
  use Dawarich.JobsCase

  alias Dawarich.Cache.{PreheatSweepWorker, Schedule}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Redis

  setup do
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)
    {:ok, _} = Redis.cache_command(["FLUSHDB"])
    :ok
  end

  @tag a12f3b_case: "C02a"
  test "native cache sweep preserves eligible users and stable source slot" do
    rows(
      "INSERT INTO users(id,email,encrypted_password,status,settings,plan,created_at,updated_at,deleted_at) SELECT 190000+n,'native-sweep-'||n||'@example.invalid','',n%4,'{}',1,now(),now(),CASE WHEN n=503 THEN now() END FROM generate_series(0,503) n"
    )

    Ownership.put!(ScratchRepo, PreheatSweepWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:cache.preheat_user", :oban)
    due = 1_791_032_400

    for self_hosted <- [false, true] do
      rows("DELETE FROM oban.oban_jobs")
      source = Ecto.UUID.generate()

      opts = [
        source_job_id: source,
        clock: due - 3600,
        schedule_in: 3600,
        time_zone: "Asia/Tokyo",
        env: %{"SELF_HOSTED" => to_string(self_hosted)}
      ]

      assert PreheatSweepWorker.run(ScratchRepo, opts) == :ok

      children =
        rows("SELECT args,scheduled_at FROM oban.oban_jobs ORDER BY (args->>'user_id')::integer")

      expected = for n <- 0..502, self_hosted or rem(n, 4) in [1, 2], do: 190_000 + n
      assert Enum.map(children, fn [args, _] -> args["user_id"] end) == expected

      for [args, at] <- children do
        assert args["time_zone"] == "Asia/Tokyo"
        expected_source = :crypto.hash(:md5, "#{source}/#{args["user_id"]}") |> Ecto.UUID.load!()
        assert args["source_job_id"] == expected_source
        assert args["event_id"] == args["source_job_id"]
        assert args["sweep_source_job_id"] == nil
        assert NaiveDateTime.compare(at, DateTime.from_unix!(due) |> DateTime.to_naive()) == :eq
      end

      assert PreheatSweepWorker.run(ScratchRepo, opts) == :ok

      assert rows(
               "SELECT args,scheduled_at FROM oban.oban_jobs ORDER BY (args->>'user_id')::integer"
             ) == children

      assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    end

    Ownership.put!(ScratchRepo, PreheatSweepWorker.key(), :sidekiq)
    Ownership.put!(ScratchRepo, "command:cache.preheat_user", :sidekiq, pinned: true)
    assert PreheatSweepWorker.run(ScratchRepo) == {:cancel, :not_owner}
    accepted = Ecto.UUID.generate()

    assert PreheatSweepWorker.perform(%Oban.Job{
             id: 1,
             args: %{"source_job_id" => accepted, "time_zone" => "Asia/Tokyo"},
             scheduled_at: DateTime.from_unix!(due)
           }) == :ok

    expected_source = :crypto.hash(:md5, "#{accepted}/190001") |> Ecto.UUID.load!()

    assert [[args, at]] =
             rows("SELECT args,scheduled_at FROM oban.oban_jobs WHERE args->>'event_id'=$1", [
               expected_source
             ])

    assert args["source_job_id"] == expected_source
    assert args["time_zone"] == "Asia/Tokyo"
    assert NaiveDateTime.compare(at, DateTime.from_unix!(due) |> DateTime.to_naive()) == :eq
    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
  end

  @tag a12f3b_case: "C02b"
  test "native boot cannot schedule Rails cleaning or consume source sentinel" do
    assert Process.whereis(Dawarich.Supervisor)
    {:ok, "OK"} = Redis.cache_command(["SET", "cache_jobs_scheduled", "source-boot-sentinel"])
    plan = Dawarich.Application.plan(~w(dawarich start), %{"DAWARICH_RAILS" => "off"})
    assert {:native, _} = plan

    script = """
    Application.put_all_env(Config.Reader.read!("config/config.exs", env: :test))
    Application.put_all_env(Config.Reader.read!("config/runtime.exs", env: :test))
    {:ok, _} = Application.ensure_all_started(:redix)
    {:ok, _} = Redix.start_link(System.fetch_env!("PHOENIX_TEST_REDIS_URL"), name: Dawarich.Redis.Cache, database: 0)
    {:ok, _} = Application.ensure_all_started(:dawarich)
    {:ok, "source-boot-sentinel"} = Dawarich.Redis.cache_command(["GET", "cache_jobs_scheduled"])
    [[cleaning]] = Dawarich.Repo.query!("SELECT count(*) FROM phoenix.rails_commands WHERE kind='cache.cleaning'").rows
    IO.puts("cache-cleaning-count=" <> Integer.to_string(cleaning))
    0 = cleaning
    [[0]] = Dawarich.Repo.query!("SELECT count(*) FROM public.job_outbox WHERE command_type LIKE 'cache.clean%'").rows
    false = Enum.any?(Supervisor.which_children(Dawarich.Supervisor), fn {id, _, _, _} -> id == Dawarich.RailsServer end)
    """

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd("elixir", paths ++ ["-e", script],
        stderr_to_stdout: true,
        env: [
          {"DAWARICH_RAILS", "on"},
          {"DAWARICH_PROCESS_ROLE", "web"},
          {"DAWARICH_PHOENIX_LIFECYCLE", "false"}
        ]
      )

    assert status == 0,
           Enum.find(
             String.split(output, "\n"),
             &String.starts_with?(&1, "cache-cleaning-count=")
           ) || "isolated boot failed"

    children = Dawarich.Application.children(plan)
    refute Enum.any?(children, &(Supervisor.child_spec(&1, []).id == Dawarich.RailsServer))
    assert {:ok, "source-boot-sentinel"} = Redis.cache_command(["GET", "cache_jobs_scheduled"])
    Ownership.put!(ScratchRepo, "command:cache.preheat_user", :oban)
    source = Ecto.UUID.generate()

    assert Schedule.preheat_user(ScratchRepo, 14101,
             source_job_id: source,
             time_zone: "Asia/Tokyo",
             clock: 1_791_028_800
           ) == :ok

    assert [[args, at]] = rows("SELECT args,scheduled_at FROM oban.oban_jobs")
    assert args["source_job_id"] == source
    assert args["time_zone"] == "Asia/Tokyo"
    assert NaiveDateTime.compare(at, ~N[2026-10-03 12:00:00]) == :eq
    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    assert [[0]] = rows("SELECT count(*) FROM public.job_outbox")
    native = "phoenix/dawarich/user_14101_total_distance"
    summary = [%{distance: 1000, toponyms: []}]
    assert Dawarich.Cache.Readers.summary(14101, summary).total_distance == 1000
    {:ok, 1} = Redis.cache_command(["PEXPIRE", native, "0"])
    assert {:ok, nil} = Redis.cache_command(["GET", native])

    assert Dawarich.Cache.Readers.summary(14101, [%{distance: 2000, toponyms: []}]).total_distance ==
             2000

    assert {:ok, ttl} = Redis.cache_command(["TTL", native])
    assert ttl in 1..86400
    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
  end
end
