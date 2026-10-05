defmodule Dawarich.Places.OrphansTest do
  use Dawarich.JobsCase

  alias Dawarich.Places.{DeleteIfOrphanWorker, Orphans}

  setup do
    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES ('orphans@example.test',now(),now()) RETURNING id"
      )

    [[other]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES ('other-orphans@example.test',now(),now()) RETURNING id"
      )

    on_exit(fn ->
      rows(
        "DELETE FROM place_visits WHERE place_id IN (SELECT id FROM places WHERE user_id=ANY($1))",
        [[user, other]]
      )

      rows(
        "UPDATE visits SET place_id=NULL WHERE place_id IN (SELECT id FROM places WHERE user_id=ANY($1))",
        [[user, other]]
      )

      rows(
        "DELETE FROM taggings WHERE taggable_type='Place' AND taggable_id IN (SELECT id FROM places WHERE user_id=ANY($1))",
        [[user, other]]
      )

      rows("DELETE FROM places WHERE user_id=ANY($1)", [[user, other]])
    end)

    %{user: user, other: other}
  end

  test "deletes only eligible owned suggested orphan and detaches hidden references", %{
    user: user,
    other: other
  } do
    target = place(user, 1, " \t\n")
    declined = visit(user, target, 2, nil)
    deleted = visit(user, target, 1, ~N[2026-10-04 00:00:00.000000])
    link(target, declined)
    link(target, deleted)
    sentinel = place(other, 1, nil)
    sentinel_visit = visit(other, sentinel, 2, nil)
    link(sentinel, sentinel_visit)
    manual = place(user, 0, nil)
    gpx = place(user, 2, nil)
    noted = place(user, 1, "keep")
    tagged = place(user, 1, nil)
    active = place(user, 1, nil)
    visit(user, active, 0, nil)

    [[tag]] =
      rows(
        "INSERT INTO tags(user_id,name,created_at,updated_at) VALUES($1,'Synthetic tag',now(),now()) RETURNING id",
        [user]
      )

    rows(
      "INSERT INTO taggings(tag_id,taggable_id,taggable_type,created_at,updated_at) VALUES($1,$2,'Place',now(),now())",
      [tag, tagged]
    )

    for id <- [sentinel, manual, gpx, noted, tagged, active],
        do: refute(Orphans.delete(ScratchRepo, user, id))

    assert Orphans.delete(ScratchRepo, user, target)

    assert rows("SELECT place_id FROM visits WHERE id IN ($1,$2)", [declined, deleted]) == [
             [nil],
             [nil]
           ]

    assert rows("SELECT count(*) FROM place_visits WHERE place_id=$1", [target]) == [[0]]
    refute Orphans.delete(ScratchRepo, user, target)
    assert rows("SELECT count(*) FROM places WHERE id=$1", [sentinel]) == [[1]]
    assert rows("SELECT place_id FROM visits WHERE id=$1", [sentinel_visit]) == [[sentinel]]
    assert rows("SELECT count(*) FROM place_visits WHERE place_id=$1", [sentinel]) == [[1]]

    payload = %{"user_id" => user, "place_id" => sentinel}
    assert DeleteIfOrphanWorker.args_from_command(1, payload) == {:ok, payload}

    for p <- [
          Map.put(payload, "extra", 1),
          Map.put(payload, "user_id", "1"),
          Map.delete(payload, "place_id")
        ],
        do: assert(DeleteIfOrphanWorker.args_from_command(1, p) == {:error, "invalid_payload"})

    assert DeleteIfOrphanWorker.args_from_command(2, payload) == {:error, "unsupported_version"}
    victim = place(user, 1, nil)
    args = %{"user_id" => user, "place_id" => victim, "event_id" => Ecto.UUID.generate()}
    assert DeleteIfOrphanWorker.run(ScratchRepo, args) == :ok
    assert DeleteIfOrphanWorker.run(ScratchRepo, args) == :ok
    assert Dawarich.Jobs.Processed.done?(ScratchRepo, args["event_id"])
    assert rows("SELECT count(*) FROM places WHERE id=$1", [victim]) == [[0]]
    assert DeleteIfOrphanWorker.__opts__()[:max_attempts] == 26
  end

  test "new active reference or FK conflict keeps the place and references intact", %{user: user} do
    target = place(user, 1, nil)
    hidden = visit(user, target, 2, nil)
    link(target, hidden)

    holder =
      Dawarich.LockRace.hold(fn ->
        rows("SELECT id FROM places WHERE id=$1 FOR UPDATE", [target])
        visit(user, target, 0, nil)
      end)

    deletion = Dawarich.LockRace.attempt(fn -> Orphans.delete(ScratchRepo, user, target) end)

    assert Dawarich.LockRace.settle(deletion, "SELECT source, note FROM places%FOR UPDATE") ==
             :blocked

    Dawarich.LockRace.commit(holder)
    assert Task.await(deletion) == {:ok, false}
    assert rows("SELECT count(*) FROM visits WHERE place_id=$1", [target]) == [[2]]
    assert rows("SELECT count(*) FROM place_visits WHERE place_id=$1", [target]) == [[1]]

    constrained = place(user, 1, nil)
    hidden = visit(user, constrained, 2, nil)
    link(constrained, hidden)

    rows(
      "CREATE TABLE public.a12d2_orphan_reference(place_id bigint REFERENCES public.places(id))"
    )

    try do
      rows("INSERT INTO public.a12d2_orphan_reference(place_id) VALUES($1)", [constrained])
      refute Orphans.delete(ScratchRepo, user, constrained)
      args = %{"user_id" => user, "place_id" => constrained, "event_id" => Ecto.UUID.generate()}
      assert DeleteIfOrphanWorker.run(ScratchRepo, args) == :ok
      assert Dawarich.Jobs.Processed.done?(ScratchRepo, args["event_id"])
      assert rows("SELECT place_id FROM visits WHERE id=$1", [hidden]) == [[constrained]]
      assert rows("SELECT count(*) FROM place_visits WHERE place_id=$1", [constrained]) == [[1]]
      assert rows("SELECT count(*) FROM places WHERE id=$1", [constrained]) == [[1]]
    after
      rows("DROP TABLE public.a12d2_orphan_reference")
    end

    args = %{"user_id" => user, "place_id" => constrained, "event_id" => Ecto.UUID.generate()}

    rows(
      "ALTER TABLE visits ADD CONSTRAINT a12d2_orphan_update_failure CHECK(place_id IS NOT NULL) NOT VALID"
    )

    try do
      assert_raise Postgrex.Error, fn -> DeleteIfOrphanWorker.run(ScratchRepo, args) end
      refute Dawarich.Jobs.Processed.done?(ScratchRepo, args["event_id"])
      assert rows("SELECT place_id FROM visits WHERE id=$1", [hidden]) == [[constrained]]
    after
      rows("ALTER TABLE visits DROP CONSTRAINT a12d2_orphan_update_failure")
    end
  end

  defp place(user, source, note) do
    [[id]] =
      rows(
        "INSERT INTO places(user_id,name,source,note,latitude,longitude,created_at,updated_at) VALUES($1,'Synthetic orphan',$2,$3,0,0,now(),now()) RETURNING id",
        [user, source, note]
      )

    id
  end

  defp visit(user, place, status, deleted) do
    [[id]] =
      rows(
        "INSERT INTO visits(user_id,place_id,name,status,deleted_at,duration,started_at,ended_at,created_at,updated_at) VALUES($1,$2,'Synthetic visit',$3,$4,60,timestamp '2026-10-04'+(SELECT count(*) FROM visits WHERE place_id=$2)*interval '1 minute',timestamp '2026-10-05',now(),now()) RETURNING id",
        [user, place, status, deleted]
      )

    id
  end

  defp link(place, visit),
    do:
      rows(
        "INSERT INTO place_visits(place_id,visit_id,created_at,updated_at) VALUES($1,$2,now(),now())",
        [place, visit]
      )
end
