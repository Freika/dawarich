defmodule Dawarich.Visits.CommandsTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.Accounts.Scope
  alias Dawarich.Visits.Commands
  alias Dawarich.Repo
  alias Dawarich.Test.FrameSeeds, as: S
  @now ~U[2026-10-03 10:00:00Z]
  @opts [now: @now, self_hosted: true]
  setup do
    user = S.user!(8511)
    foreign = S.user!(8512)

    S.visit!(user.id, 85001, %{
      started_at: ~N[2026-09-30 09:00:00],
      ended_at: ~N[2026-09-30 10:00:00],
      status: 0,
      duration: 60
    })

    S.visit!(user.id, 85002, %{
      started_at: ~N[2026-09-30 11:00:00],
      ended_at: ~N[2026-09-30 12:00:00],
      status: 0,
      duration: 60
    })

    S.visit!(foreign.id, 85003, %{
      started_at: ~N[2026-09-30 09:00:00],
      ended_at: ~N[2026-09-30 10:00:00],
      status: 0,
      duration: 60
    })

    %{scope: Scope.for_user(user, "de")}
  end

  test "visit commands re-admit every selected row and publish old and new months once", %{
    scope: scope
  } do
    assert {:error, :missing} =
             Commands.bulk_update(
               scope,
               %{"visit_ids" => ["85001", "85003"], "status" => "confirmed"},
               @opts
             )

    assert jobs() == []
    assert statuses() == [[85001, 0], [85002, 0], [85003, 0]]

    assert {:ok, changed} =
             Commands.update(
               scope,
               "85001",
               %{"started_at" => "2026-10-01T09:00:00Z", "ended_at" => "2026-10-01T10:00:00Z"},
               @opts
             )

    assert changed.ids == [85001]
    assert changed.days == ["2026-09-30", "2026-10-01"]
    assert Map.keys(changed.month_revisions) |> Enum.sort() == ["2026-09", "2026-10"]
    assert Enum.all?(Map.values(changed.month_revisions), &is_binary/1)
    assert length(jobs()) == 1

    assert Enum.map(hd(jobs())["started_at"], fn value ->
             {:ok, at, _} = DateTime.from_iso8601(value)
             DateTime.to_unix(at)
           end) == [
             DateTime.to_unix(~U[2026-09-30 09:00:00Z]),
             DateTime.to_unix(~U[2026-10-01 09:00:00Z])
           ]

    Repo.query!(
      "UPDATE users SET encrypted_password='changed-identity-000000000000000000' WHERE id=$1",
      [scope.user.id],
      log: false
    )

    assert {:error, :stale_session} = Commands.delete(scope, "85002", @opts)
    assert length(jobs()) == 1
  end

  test "visit merge refuses different local days with no effects", %{scope: scope} do
    Repo.query!(
      "UPDATE visits SET started_at='2026-10-01 09:00:00',ended_at='2026-10-01 10:00:00' WHERE id=85002",
      [],
      log: false
    )

    assert {:error, :visits_must_share_day} = Commands.merge(scope, ["85001", "85002"], @opts)
    assert statuses() == [[85001, 0], [85002, 0], [85003, 0]]
    assert jobs() == []
    assert {:error, :too_many} = Commands.merge(scope, Enum.map(1..501, &to_string/1), @opts)
  end

  test "bulk failure rolls back changes and refresh intent", %{scope: scope} do
    Repo.query!(
      "CREATE FUNCTION pg_temp.refuse_visit_epoch() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'synthetic refusal'; END$$",
      [],
      log: false
    )

    Repo.query!(
      "CREATE TRIGGER native_visit_epoch_failure BEFORE INSERT OR UPDATE ON phoenix.epochs FOR EACH ROW EXECUTE FUNCTION pg_temp.refuse_visit_epoch()",
      [],
      log: false
    )

    assert {:error, :unavailable} =
             Commands.bulk_update(
               scope,
               %{"visit_ids" => ["85001", "85002"], "status" => "confirmed"},
               @opts
             )

    assert statuses() == [[85001, 0], [85002, 0], [85003, 0]]
    assert jobs() == []

    assert Repo.query!(
             "SELECT count(*) FROM phoenix.epochs WHERE key LIKE 'timeline_visit_month/8511/%'",
             [],
             log: false
           ).rows == [[0]]

    Repo.query!("DROP TRIGGER native_visit_epoch_failure ON phoenix.epochs", [], log: false)

    assert {:ok, result} =
             Commands.bulk_update(
               scope,
               %{"visit_ids" => ["85001", "85002"], "status" => "confirmed"},
               @opts
             )

    assert result.notice == "controllers.visits.bulk_updated.confirmed"
    assert result.bindings == %{count: 2}
    assert length(jobs()) == 1
  end

  test "visit command identifiers are bounded before writes and removals return source notices",
       %{scope: scope} do
    assert {:error, :invalid_input} = Commands.delete(scope, String.duplicate("9", 128), @opts)
    assert jobs() == []
    assert {:ok, merged} = Commands.merge(scope, ["85001", "85002"], @opts)
    assert merged.ids == [85001, 85002]
    assert merged.notice == "controllers.visits.visits_merged"
    assert {:ok, deleted} = Commands.delete(scope, "85001", @opts)
    assert deleted.notice == "controllers.visits.visit_removed"

    for id <- [85004, 85005],
        do:
          S.visit!(scope.user.id, id, %{
            started_at: ~N[2026-09-30 09:00:00],
            ended_at: ~N[2026-09-30 10:00:00],
            status: 0
          })

    assert {:ok, bulk} = Commands.bulk_delete(scope, %{"visit_ids" => ["85004", "85005"]}, @opts)
    assert bulk.ids == [85004, 85005]
    assert bulk.bindings == %{count: 2}
    assert bulk.notice == "controllers.visits.bulk_removed"

    assert Repo.query!("SELECT deleted_at FROM visits WHERE id=85003", [], log: false).rows == [
             [nil]
           ]
  end

  defp jobs,
    do:
      Repo.query!(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Points.VisitMonthsWorker' ORDER BY id",
        [],
        log: false
      ).rows
      |> Enum.map(&hd/1)

  defp statuses,
    do:
      Repo.query!("SELECT id,status FROM visits WHERE id IN (85001,85002,85003) ORDER BY id", [],
        log: false
      ).rows
end
