defmodule Dawarich.ReleaseMigrations.MapMatchingDeadlineTest do
  use Dawarich.ScratchCase, async: true, group: :scratch_case_db

  alias Dawarich.{ReleaseMigration, ReleaseMigrator}
  alias Dawarich.ReleaseMigrator.Floor
  alias Dawarich.ReleaseMigrations.Unreleased

  defmodule DeadlineRepo do
    use Ecto.Repo, otp_app: :dawarich, adapter: Ecto.Adapters.Postgres
  end

  setup do
    config =
      ScratchRepo.config()
      |> Keyword.drop([:timeout, :telemetry_prefix])
      |> Keyword.put(:pool_size, 4)

    start_supervised!({DeadlineRepo, config})
    scratch_sql!("CREATE EXTENSION IF NOT EXISTS postgis")
    scratch_sql!("CREATE TABLE tracks(id bigint)")
    scratch_sql!("INSERT INTO tracks VALUES (1), (1)")
    :ok
  end

  test "concurrent map-matching index rebuild survives a writer beyond the production deadline" do
    {_, columns, true} =
      Unreleased.steps() |> List.keyfind("20261006120000", 0) |> ReleaseMigration.normalize()

    assert {:ok, :ok} = ScratchRepo.transaction(fn -> columns.(ScratchRepo) end)
    ledger_except!("20261006120100")

    assert_raise Postgrex.Error, ~r/unique_violation/, fn ->
      scratch_sql!("CREATE UNIQUE INDEX CONCURRENTLY index_tracks_on_matched_path ON tracks(id)")
    end

    assert index_validity() == [[false]]

    {_, index, false} =
      Unreleased.steps() |> List.keyfind("20261006120100", 0) |> ReleaseMigration.normalize()

    assert :ok = index.(DeadlineRepo)
    assert index_validity() == [[true]]
    scratch_sql!("DROP INDEX CONCURRENTLY index_tracks_on_matched_path")
    blocker = hold_lock!("UPDATE tracks SET id = id", :deadline)
    started = System.monotonic_time(:millisecond)

    result =
      try do
        ReleaseMigrator.apply_release_for_proof(DeadlineRepo, Unreleased)
      after
        send(blocker.pid, :release)
        assert {:ok, :ok} = Task.await(blocker, :infinity)
      end

    assert {:ok, %{applied: ["20261006120100"]}} = result
    assert System.monotonic_time(:millisecond) - started >= 15_000
    assert index_validity() == [[true]]

    assert [[definition]] =
             ScratchRepo.query!(
               "SELECT indexdef FROM pg_indexes WHERE schemaname='public' AND indexname='index_tracks_on_matched_path'"
             ).rows

    assert definition =~ "USING gist (matched_path) WHERE (matched_path IS NOT NULL)"

    assert {:ok, %{applied: []}} =
             ReleaseMigrator.apply_release_for_proof(DeadlineRepo, Unreleased)
  end

  test "atomic map-matching column migration survives two lock waits with the production runner" do
    ledger_except!("20261006120000")
    blocker = hold_lock!("LOCK TABLE tracks IN ACCESS SHARE MODE", :two_retries)
    handler = {__MODULE__, make_ref()}
    parent = self()

    :ok =
      :telemetry.attach(
        handler,
        DeadlineRepo.config()[:telemetry_prefix] ++ [:query],
        fn _, _, metadata, _ ->
          case metadata.result do
            {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}} ->
              send(parent, :lock_retry)
              send(blocker.pid, :lock_retry)

            _ ->
              :ok
          end
        end,
        nil
      )

    result =
      try do
        ReleaseMigrator.apply_release_for_proof(DeadlineRepo, Unreleased)
      after
        send(blocker.pid, :release)
        assert {:ok, :ok} = Task.await(blocker, :infinity)
        :telemetry.detach(handler)
      end

    assert {:ok, %{applied: ["20261006120000"]}} = result
    assert_received :lock_retry
    assert_received :lock_retry
    assert_received {:visible_columns, [["id"]]}

    assert ScratchRepo.query!(
             "SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='tracks'"
           ).rows == [[6]]

    assert ScratchRepo.query!("SELECT id, map_matching_data FROM tracks ORDER BY id").rows == [
             [1, %{}],
             [1, %{}]
           ]

    assert {:ok, %{applied: []}} =
             ReleaseMigrator.apply_release_for_proof(DeadlineRepo, Unreleased)
  end

  defp hold_lock!(sql, mode) do
    parent = self()

    blocker =
      Task.async(fn ->
        DeadlineRepo.transaction(
          fn ->
            DeadlineRepo.query!(sql, [], log: false)
            send(parent, {:locked, self()})
            await_release(mode, parent)
          end,
          timeout: :infinity
        )
      end)

    assert_receive {:locked, pid} when pid == blocker.pid
    blocker
  end

  defp await_release(:deadline, _) do
    receive do
      :release -> :ok
    after
      16_000 -> :ok
    end
  end

  defp await_release(:two_retries, parent) do
    receive do
      :release ->
        :ok

      :lock_retry ->
        receive do
          :release ->
            :ok

          :lock_retry ->
            rows =
              DeadlineRepo.query!(
                "SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='tracks'"
              ).rows

            send(parent, {:visible_columns, rows})
            :ok
        end
    end
  end

  defp ledger_except!(version) do
    scratch_sql!("CREATE TABLE schema_migrations(version varchar PRIMARY KEY)")

    for item <- Floor.versions() ++ ReleaseMigration.versions(Unreleased), item != version do
      ScratchRepo.query!("INSERT INTO schema_migrations VALUES ($1) ON CONFLICT DO NOTHING", [
        item
      ])
    end
  end

  defp index_validity do
    ScratchRepo.query!(
      "SELECT indisvalid FROM pg_index WHERE indexrelid=to_regclass('index_tracks_on_matched_path')"
    ).rows
  end
end
