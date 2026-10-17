defmodule Dawarich.A12f3bR11Test do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.DestroyEffects
  setup do: {:ok, F.destroy(F.setup())}

  @tag a12f3b_case: "R11k01"
  test "imports.destroy_callbacks native producer reaches its source terminal effect", c do
    [[place]] =
      rows(
        "INSERT INTO places(user_id,name,source,latitude,longitude,created_at,updated_at) VALUES($1,'orphan',1,52,13,now(),now()) RETURNING id",
        [c.import.user_id]
      )

    [[foreign]] =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,created_at,updated_at) VALUES($1,'foreign',52,13,now(),now()) RETURNING id",
        [c.other]
      )

    assert {:ok, :ok} =
             F.with_destroy(c, fn lease ->
               Dawarich.Imports.DestroyLease.effect!(lease, fn ->
                 DestroyEffects.callback!(lease, "places_cleanup", %{
                   "place_ids" => [place, foreign]
                 })

                 :ok
               end)
             end)

    assert [] == F.reverse()

    [[args]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Places.DeleteIfOrphanWorker'")

    assert args["place_id"] == place
    assert :ok == Dawarich.Places.DeleteIfOrphanWorker.run(ScratchRepo, args)
    assert [[foreign]] == rows("SELECT id FROM places WHERE id=ANY($1)", [[place, foreign]])
  end

  @tag a12f3b_case: "R11k02"
  test "imports.destroy_complete native producer reaches its source terminal effect", c do
    Dawarich.Imports.Events.subscribe(c.import.user_id)

    assert {:ok, :ok} =
             F.with_destroy(c, fn lease ->
               DestroyEffects.status!(lease)
               drain_events()
               assert_receive :imports_changed

               Dawarich.Imports.DestroyLease.effect!(lease, fn ->
                 rows("DELETE FROM imports WHERE id=$1", [c.import.id])

                 rows(
                   "UPDATE phoenix.import_destroy_runs SET phase='removed' WHERE import_id=$1",
                   [c.import.id]
                 )
               end)

               DestroyEffects.finish!(lease)
               :ok
             end)

    drain_events()
    assert_receive :imports_changed
    assert [] == F.reverse()
    assert Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])
  end

  defp drain_events do
    for [args] <-
          rows(
            "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Imports.EventsWorker' ORDER BY id"
          ) do
      assert :ok == Dawarich.Imports.EventsWorker.run(ScratchRepo, args)
    end
  end

  @tag a12f3b_case: "R11k03"
  test "imports.destroy_terminal native producer reaches its source terminal effect", c do
    assert {:ok, _} =
             F.with_destroy(c, fn lease ->
               Dawarich.Imports.DestroyLease.effect!(lease, fn ->
                 rows("DELETE FROM imports WHERE id=$1", [c.import.id])

                 rows(
                   "UPDATE phoenix.import_destroy_runs SET phase='removed' WHERE import_id=$1",
                   [c.import.id]
                 )
               end)
             end)

    assert :ok == Dawarich.Imports.DestroyHandover.resume(ScratchRepo, c.job)
    assert :ok == Dawarich.Imports.DestroyHandover.resume(ScratchRepo, c.job)
    assert [] == F.reverse()
    assert Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])
  end

  @tag a12f3b_case: "R11k04"
  test "imports.destroy_achievements native producer reaches its source terminal effect", c do
    assert {:ok, :ok} =
             F.with_destroy(c, fn lease ->
               Dawarich.Imports.DestroyLease.effect!(lease, fn ->
                 for oldest <- [100, 50],
                     do:
                       DestroyEffects.insert!(lease, "imports.destroy_achievements", %{
                         "oldest_timestamp" => oldest
                       })

                 :ok
               end)
             end)

    assert [] == F.reverse()
    assert ["Dawarich.Achievements.CheckWorker"] == F.workers()

    assert [[%{"user_id" => user, "notify" => true, "oldest_timestamp" => 50, "event_id" => _}]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.CheckWorker'"
             )

    assert user == c.import.user_id
  end

  @tag a12f3b_case: "R11k05"
  test "imports.destroy_stats native producer reaches its source terminal effect", c do
    rows(
      "INSERT INTO stats(user_id,year,month,distance,created_at,updated_at) VALUES($1,2025,12,0,now(),now())",
      [c.import.user_id]
    )

    rows("UPDATE users SET points_count=1,settings=$2 WHERE id=$1", [
      c.import.user_id,
      %{"timezone" => "Europe/Berlin"}
    ])

    rows(
      "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,1767222000,ST_SetSRID(ST_MakePoint(13,52),4326)::geography,now(),now())",
      [c.import.user_id, c.import.id]
    )

    assert :ok == Dawarich.Imports.DestroyWorker.perform(c.job)
    assert [] == rows("SELECT id FROM imports WHERE id=$1", [c.import.id])
    assert [] == F.reverse()

    assert [[2025, 12], [2026, 1]] ==
             rows(
               "SELECT (args->>'year')::int,(args->>'month')::int FROM oban.oban_jobs WHERE worker='Dawarich.Stats.CalculateMonthWorker' ORDER BY 1,2"
             )

    assert [[0]] == rows("SELECT points_count FROM users WHERE id=$1", [c.import.user_id])
  end
end
