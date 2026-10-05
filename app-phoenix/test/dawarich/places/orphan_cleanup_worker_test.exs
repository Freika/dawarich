defmodule Dawarich.Places.OrphanCleanupWorkerTest do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Places.OrphanCleanupWorker, as: Worker
  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)

    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES('cleanup@example.test',now(),now()) RETURNING id"
      )

    [[other]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES('cleanup-other@example.test',now(),now()) RETURNING id"
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

    Ownership.put!(ScratchRepo, "command:places.orphan_cleanup", :oban)

    %{
      user: user,
      other: other,
      args: %{"user_id" => user, "event_id" => Ecto.UUID.generate(), "cursor" => 0}
    }
  end

  test "cleanup drains source-sized user batches preserving custom and referenced places", %{
    user: user,
    other: other,
    args: args
  } do
    custom = place(user, 0, nil)
    gpx = place(user, 2, nil)
    noted = place(user, 1, "keep")
    whitespace = place(user, 1, " \n")
    active = place(user, 1, nil)
    visit(user, active, 0)
    tagged = place(user, 1, nil)

    [[tag]] =
      rows(
        "INSERT INTO tags(user_id,name,created_at,updated_at) VALUES($1,'Synthetic tag',now(),now()) RETURNING id",
        [user]
      )

    rows(
      "INSERT INTO taggings(tag_id,taggable_id,taggable_type,created_at,updated_at) VALUES($1,$2,'Place',now(),now())",
      [tag, tagged]
    )

    sentinel = place(other, 1, nil)

    victims =
      rows(
        "INSERT INTO places(user_id,name,source,latitude,longitude,created_at,updated_at) SELECT $1,'Synthetic victim',1,0,0,now(),now() FROM generate_series(1,501) RETURNING id",
        [user]
      )
      |> List.flatten()

    hidden = visit(user, hd(victims), 2)

    rows(
      "INSERT INTO place_visits(place_id,visit_id,created_at,updated_at) VALUES($1,$2,now(),now())",
      [hd(victims), hidden]
    )

    assert Worker.args_from_command(1, %{"user_id" => user}) ==
             {:ok, %{"user_id" => user, "cursor" => 0}}

    assert Worker.args_from_command(1, %{"user_id" => user, "cursor" => 1}) ==
             {:error, "invalid_payload"}

    assert Worker.args_from_command(2, %{"user_id" => user}) == {:error, "unsupported_version"}
    assert Worker.run(ScratchRepo, @oban, args) == :ok
    assert rows("SELECT count(*) FROM places WHERE id=ANY($1)", [victims]) == [[1]]
    assert rows("SELECT place_id FROM visits WHERE id=$1", [hidden]) == [[nil]]
    assert rows("SELECT count(*) FROM place_visits WHERE visit_id=$1", [hidden]) == [[0]]

    [[next]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
        "Dawarich.Places.OrphanCleanupWorker"
      ])

    assert next["cursor"] == Enum.at(victims, 499)
    assert Worker.run(ScratchRepo, @oban, next) == :ok
    assert Worker.run(ScratchRepo, @oban, args) == :ok
    assert Worker.run(ScratchRepo, @oban, next) == :ok
    assert rows("SELECT count(*) FROM places WHERE id=ANY($1)", [victims]) == [[0]]

    assert rows("SELECT id FROM places WHERE user_id=ANY($1) ORDER BY id", [[user, other]]) ==
             Enum.map([custom, gpx, noted, whitespace, active, tagged, sentinel], &[&1])

    assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [
             "Dawarich.Places.OrphanCleanupWorker"
           ]) == [[1]]

    assert Worker.__opts__()[:max_attempts] == 26
  end

  test "batch rollback retries remaining victims without affecting committed batches", %{
    user: user,
    args: args
  } do
    victims =
      rows(
        "INSERT INTO places(user_id,name,source,latitude,longitude,created_at,updated_at) SELECT $1,'Synthetic rollback',1,0,0,now(),now() FROM generate_series(1,502) RETURNING id",
        [user]
      )
      |> List.flatten()

    assert Worker.run(ScratchRepo, @oban, args) == :ok

    [[next]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
        "Dawarich.Places.OrphanCleanupWorker"
      ])

    remaining = Enum.drop(victims, 500)
    hidden = visit(user, hd(remaining), 2)

    rows(
      "INSERT INTO place_visits(place_id,visit_id,created_at,updated_at) VALUES($1,$2,now(),now())",
      [hd(remaining), hidden]
    )

    assert_raise Postgrex.Error, fn ->
      Worker.run(ScratchRepo, @oban, next,
        hook: fn
          {:deleting, _id} -> rows("SELECT 1/0")
          _ -> :ok
        end
      )
    end

    refute Processed.done?(ScratchRepo, Worker.batch_id(next))

    assert rows("SELECT id FROM places WHERE user_id=$1 ORDER BY id", [user]) ==
             Enum.map(remaining, &[&1])

    assert rows("SELECT place_id FROM visits WHERE id=$1", [hidden]) == [[hd(remaining)]]
    assert rows("SELECT count(*) FROM place_visits WHERE visit_id=$1", [hidden]) == [[1]]
    assert Processed.done?(ScratchRepo, Worker.batch_id(args))

    rows(
      "CREATE TABLE public.a12d2_cleanup_reference(place_id bigint REFERENCES public.places(id))"
    )

    try do
      rows("INSERT INTO public.a12d2_cleanup_reference(place_id) VALUES($1)", [
        List.last(remaining)
      ])

      assert_raise Postgrex.Error, fn -> Worker.run(ScratchRepo, @oban, next) end
      refute Processed.done?(ScratchRepo, Worker.batch_id(next))

      assert rows("SELECT id FROM places WHERE user_id=$1 ORDER BY id", [user]) ==
               Enum.map(remaining, &[&1])

      assert rows("SELECT place_id FROM visits WHERE id=$1", [hidden]) == [[hd(remaining)]]
      assert rows("SELECT count(*) FROM place_visits WHERE visit_id=$1", [hidden]) == [[1]]
    after
      rows("DROP TABLE public.a12d2_cleanup_reference")
    end

    target = hd(remaining)

    holder =
      Dawarich.LockRace.hold(fn ->
        rows("SELECT id FROM places WHERE id=$1 FOR UPDATE", [target])
        visit(user, target, 0)
      end)

    attempt = Dawarich.LockRace.attempt(fn -> Worker.run(ScratchRepo, @oban, next) end)

    assert Dawarich.LockRace.settle(attempt, "SELECT source, note FROM places%FOR UPDATE") ==
             :blocked

    Dawarich.LockRace.commit(holder)
    assert Task.await(attempt) == {:ok, :ok}
    assert rows("SELECT id FROM places WHERE user_id=$1", [user]) == [[target]]
    assert rows("SELECT count(*) FROM visits WHERE place_id=$1", [target]) == [[2]]
    assert rows("SELECT count(*) FROM place_visits WHERE place_id=$1", [target]) == [[1]]
    assert Worker.run(ScratchRepo, @oban, next) == :ok
    assert Processed.done?(ScratchRepo, Worker.batch_id(next))

    released = Map.put(next, "event_id", Ecto.UUID.generate())
    Ownership.put!(ScratchRepo, "command:places.orphan_cleanup", :sidekiq)
    assert Worker.run(ScratchRepo, @oban, released) == :ok
    assert Worker.run(ScratchRepo, @oban, released) == :ok

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
             ["places_orphan_cleanup", %{"user_id" => user}]
           ]

    assert rows("SELECT id FROM places WHERE user_id=$1", [user]) == [[target]]
  end

  defp place(user, source, note) do
    [[id]] =
      rows(
        "INSERT INTO places(user_id,name,source,note,latitude,longitude,created_at,updated_at) VALUES($1,'Synthetic retained',$2,$3,0,0,now(),now()) RETURNING id",
        [user, source, note]
      )

    id
  end

  defp visit(user, place, status) do
    [[id]] =
      rows(
        "INSERT INTO visits(user_id,place_id,name,status,duration,started_at,ended_at,created_at,updated_at) VALUES($1,$2,'Synthetic hidden',$3,60,timestamp '2026-10-04'+(SELECT count(*) FROM visits WHERE place_id=$2)*interval '1 minute',timestamp '2026-10-05',now(),now()) RETURNING id",
        [user, place, status]
      )

    id
  end
end
