defmodule Dawarich.Admin.JobHealthTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.{Repo, ScratchRepo}
  alias Dawarich.Admin.JobHealth

  defmodule MissingRepo do
    def transaction(fun), do: {:ok, fun.()}
    def query!("SET LOCAL" <> _, [], _), do: %{rows: [], columns: []}
    def query!("SELECT to_regclass" <> _, [], _), do: %{rows: [[false]], columns: ["present"]}
  end

  defmodule UnavailableRepo do
    def transaction(_fun), do: raise("synthetic unavailable read")
  end

  defmodule NoOptionalRepo do
    def transaction(fun), do: Dawarich.ScratchRepo.transaction(fun)
    def query!("SELECT to_regclass('oban.oban_jobs') IS NOT NULL", [], _), do: %{rows: [[false]]}

    def query!("SELECT to_regclass('phoenix.rails_commands_dead') IS NOT NULL", [], _),
      do: %{rows: [[false]]}

    def query!(sql, params, opts), do: Dawarich.ScratchRepo.query!(sql, params, opts)
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Dawarich.FixtureCleanup.delete!(Repo, ~w(public.job_outbox))
    :ok
  end

  test "job health alarm uses Rails freshness and overdue boundaries" do
    for name <- ~w(fresh stale absent owned_stale owned_absent overdue) do
      fixture = fixture(name)
      seed!(fixture)
      assert JobHealth.load(Repo, ScratchRepo, fixture["node"]).summary == fixture["summary"]
    end

    seed!(fixture("fresh"))

    Repo.query!(
      "INSERT INTO job_outbox(event_id, command_type, command_version, payload, scheduled_at) VALUES($1, 'trips.calculate', 1, '{}', now() - interval '299 seconds')",
      [Ecto.UUID.dump!(Ecto.UUID.generate())],
      log: false
    )

    refute JobHealth.load(Repo, ScratchRepo, "web-a").summary["alarm"]

    Repo.query!("UPDATE job_outbox SET scheduled_at = now() - interval '301 seconds'", [],
      log: false
    )

    assert JobHealth.load(Repo, ScratchRepo, "web-a").summary["alarm"]

    ScratchRepo.query!(
      "UPDATE phoenix.runtime_nodes SET beat_at = now() - interval '59 seconds' WHERE node = 'web-a'",
      [],
      log: false
    )

    assert JobHealth.load(Repo, ScratchRepo, "web-a").summary["status"] == "ok"

    ScratchRepo.query!(
      "UPDATE phoenix.runtime_nodes SET beat_at = now() - interval '61 seconds' WHERE node = 'web-a'",
      [],
      log: false
    )

    assert JobHealth.load(Repo, ScratchRepo, "web-a").summary["status"] == "stale"
  end

  test "job health gauges preserve Rails ordering and JSON shape" do
    for name <- ~w(fresh gauges) do
      fixture = fixture(name)
      seed!(fixture)
      result = JobHealth.load(Repo, ScratchRepo, fixture["node"])
      gauges = normalize(result.gauges, fixture)
      assert gauges == fixture["gauges"]
      assert JobHealth.pretty(gauges) == fixture["pretty"]
    end

    seed!(fixture("fresh"))
    optional = JobHealth.load(Repo, NoOptionalRepo, nil)
    assert optional.gauges["oban"] == []
    assert optional.gauges["rails_commands"] == nil
    result = JobHealth.load(Repo, MissingRepo, nil)
    assert result.gauges == fixture("missing")["gauges"]
    assert JobHealth.pretty(result.gauges) == nil
  end

  test "job health distinguishes missing tables from unavailable reads" do
    missing = JobHealth.load(Repo, MissingRepo, nil)
    assert missing.summary == fixture("missing")["summary"]
    assert missing.gauges == fixture("missing")["gauges"]

    assert JobHealth.load(Repo, MissingRepo, "web-a").summary == %{
             "status" => "stale",
             "alarm" => false
           }

    unavailable = JobHealth.load(Repo, UnavailableRepo, "web-a")
    assert unavailable.summary == fixture("unavailable")["summary"]
    assert unavailable.gauges == fixture("unavailable")["gauges"]
    assert Repo.query!("SHOW statement_timeout", [], log: false).rows == [["0"]]
  end

  defp fixture(name), do: Jason.decode!(File.read!("test/fixtures/admin_pages/#{name}.json"))

  defp seed!(fixture) do
    Dawarich.FixtureCleanup.delete!(Repo, ~w(public.job_outbox))

    Dawarich.FixtureCleanup.delete!(
      ScratchRepo,
      ~w(phoenix.job_owners  phoenix.runtime_nodes  phoenix.rails_commands  phoenix.rails_commands_dead  oban.oban_jobs  public.job_outbox)
    )

    now = ~U[2026-10-03 10:00:00Z]

    for owner <- fixture["rows"]["owners"] do
      ScratchRepo.query!(
        "INSERT INTO phoenix.job_owners(key, owner, pinned, updated_at, updated_by) VALUES($1, $2, $3, $4, $5)",
        [owner["key"], owner["owner"], owner["pinned"], now, owner["updated_by"]],
        log: false
      )
    end

    for node <- fixture["rows"]["nodes"] do
      {:ok, beat, _} = DateTime.from_iso8601(node["beat_at"])
      age = DateTime.diff(now, beat)

      ScratchRepo.query!(
        "INSERT INTO phoenix.runtime_nodes(node, started_at, beat_at) VALUES($1, $2, now() - make_interval(secs => $3))",
        [node["node"], ~U[2026-10-03 09:00:00Z], age],
        log: false
      )
    end

    for row <- fixture["rows"]["outbox"] do
      offset =
        case String.slice(row["event_id"], -5, 5) do
          "10001" -> -600
          "10002" -> 3600
          _ -> 0
        end

      Repo.query!(
        "INSERT INTO job_outbox(event_id, command_type, command_version, payload, state, scheduled_at, created_at) VALUES($1, $2, $3, '{}', $4, now() + make_interval(secs => $5), $6)",
        [
          Ecto.UUID.dump!(row["event_id"]),
          row["command_type"],
          row["command_version"],
          row["state"],
          offset,
          now
        ],
        log: false
      )
    end

    for row <- fixture["rows"]["rails_commands"] do
      offset =
        case row["id"] do
          10001 -> -600
          10004 -> 3600
          _ -> 0
        end

      lease = if row["leased_until"], do: "now() + interval '1 hour'", else: "NULL"

      ScratchRepo.query!(
        "INSERT INTO phoenix.rails_commands(id, kind, payload, attempts, available_at, leased_until, created_at) VALUES($1, $2, '{}', $3, now() + make_interval(secs => $4), #{lease}, $5)",
        [row["id"], row["kind"], row["attempts"], offset, now],
        log: false
      )
    end

    for row <- fixture["rows"]["rails_commands_dead"] do
      ScratchRepo.query!(
        "INSERT INTO phoenix.rails_commands_dead(id, kind, payload, attempts, last_error, created_at, died_at) VALUES($1, $2, '{}', $3, $4, $5, $5)",
        [row["id"], row["kind"], row["attempts"], row["last_error"], now],
        log: false
      )
    end

    for row <- fixture["rows"]["oban"], _ <- 1..row["count"] do
      ScratchRepo.query!(
        "INSERT INTO oban.oban_jobs(worker, state, args, queue) VALUES($1, $2, '{}', 'fixture')",
        [row["worker"], row["state"]],
        log: false
      )
    end
  end

  defp normalize(gauges, fixture) do
    for key <- ~w(outbox rails_commands),
        gauge = gauges[key],
        is_map(gauge),
        age = gauge["oldest_due_seconds"],
        not is_nil(age) do
      assert age >= 600 and age < 605
    end

    gauges =
      Enum.reduce(~w(outbox rails_commands), gauges, fn key, acc ->
        update_in(acc, [key, "oldest_due_seconds"], fn age -> if age, do: 600, else: nil end)
      end)

    nodes =
      Enum.zip(gauges["nodes"], fixture["gauges"]["nodes"])
      |> Enum.map(fn {node, expected} ->
        assert node["node"] == expected["node"]
        assert String.ends_with?(node["beat_at"], String.slice(expected["beat_at"], -6, 6))
        Map.put(node, "beat_at", expected["beat_at"])
      end)

    Map.put(gauges, "nodes", nodes)
  end
end
