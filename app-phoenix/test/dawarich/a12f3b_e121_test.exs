defmodule Dawarich.A12f3bE121Test do
  use Dawarich.GeocodingCase, async: false

  alias Dawarich.Jobs.{Dispatch, Drain, Ownership}

  alias Dawarich.Places.{
    BulkNameFetchWorker,
    DeleteIfOrphanWorker,
    JobCommands,
    NameFetchWorker,
    OrphanCleanupWorker
  }

  @oban __MODULE__.Oban

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    start_oban(@oban)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES('e121@example.test',now(),now()) RETURNING id"
      )

    %{user: user}
  end

  @tag a12f3b_case: "E121a"
  test "E121 native source shapes reach their terminal effects", %{user: user} do
    named = place(user)
    orphan = place(user)
    cleanup = place(user)
    due = DateTime.add(DateTime.utc_now(), 3600)

    for key <- ~w(name_fetch delete_if_orphan orphan_cleanup bulk_name_fetch),
        do: Ownership.put!(ScratchRepo, "command:places.#{key}", :sidekiq, pinned: true)

    assert JobCommands.name_fetch(ScratchRepo, user, named) == :ok
    assert JobCommands.orphan_places(ScratchRepo, user, [orphan, orphan, -1]) == :ok
    assert JobCommands.orphan_cleanup(ScratchRepo, user, due) == :ok
    assert JobCommands.bulk_name_fetch(ScratchRepo) == :ok
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    assert rows("SELECT command_type FROM job_outbox ORDER BY command_type") ==
             Enum.map(
               ~w(places.bulk_name_fetch places.delete_if_orphan places.name_fetch places.orphan_cleanup),
               &[&1]
             )

    assert rows("SELECT scheduled_at FROM job_outbox WHERE command_type='places.orphan_cleanup'") ==
             [[due]]

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: DateTime.add(due, 1)) == %{
             dispatched: 4
           }

    config =
      Dawarich.Geocoding.Config.resolve(ScratchRepo, %{"PHOTON_API_HOST" => "e121.example.test"})

    {url, _, _} =
      Dawarich.Geocoding.Query.build(config, {0.0, 0.0}, [limit: 1, distance_sort: true], "test")

    FakeHttp.stub(
      url,
      200,
      Jason.encode!(%{
        "type" => "FeatureCollection",
        "features" => [%{"properties" => %{"name" => "Station", "city" => "Berlin"}}]
      })
    )

    [[args]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [inspect(NameFetchWorker)])

    assert NameFetchWorker.run(ScratchRepo, args, config: config) == :ok
    assert rows("SELECT name FROM places WHERE id=$1", [named]) == [["Station, Berlin"]]

    [[args]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [inspect(DeleteIfOrphanWorker)])

    assert DeleteIfOrphanWorker.run(ScratchRepo, args) == :ok
    assert rows("SELECT id FROM places WHERE id=$1", [orphan]) == []

    Ownership.put!(ScratchRepo, "command:places.name_fetch", :oban)

    [[args]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [inspect(BulkNameFetchWorker)])

    assert BulkNameFetchWorker.run(ScratchRepo, @oban, args) == :ok

    [[child]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1 AND (args->>'place_id')::bigint=$2", [
        inspect(NameFetchWorker),
        cleanup
      ])

    assert NameFetchWorker.run(ScratchRepo, child, config: config) == :ok
    assert rows("SELECT name FROM places WHERE id=$1", [cleanup]) == [["Station, Berlin"]]

    [[args]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [inspect(OrphanCleanupWorker)])

    assert OrphanCleanupWorker.run(ScratchRepo, @oban, args) == :ok
    assert rows("SELECT id FROM places WHERE id=$1", [cleanup]) == []
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3b_case: "E121b"
  test "E121 accepted children prevent premature completion", %{user: user} do
    place(user)
    due = DateTime.add(DateTime.utc_now(), 3600)

    assert_raise Postgrex.Error, fn ->
      ScratchRepo.transaction(fn ->
        JobCommands.orphan_cleanup(ScratchRepo, user, due)
        rows("SELECT 1/0")
      end)
    end

    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert JobCommands.orphan_cleanup(ScratchRepo, user, due) == :ok
    status = Drain.status(ScratchRepo)
    assert status.counts.pending_outbox == 1
    assert status.counts.future_outbox == 1
    assert status.counts.reverse_pending == 0
    assert "pending_outbox" in status.shutdown_reasons
    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: DateTime.add(due, -1)) == %{}

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: DateTime.add(due, 1)) == %{
             dispatched: 1
           }

    status = Drain.status(ScratchRepo)
    assert status.counts.incomplete_oban == 1
    assert "incomplete_oban" in status.shutdown_reasons
    [[id, args]] = rows("SELECT id,args FROM oban.oban_jobs")
    assert OrphanCleanupWorker.run(ScratchRepo, @oban, args) == :ok
    rows("UPDATE oban.oban_jobs SET state='completed',completed_at=now() WHERE id=$1", [id])
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 0
    assert rows("SELECT count(*) FROM places WHERE user_id=$1", [user]) == [[0]]
  end

  defp place(user) do
    [[id]] =
      rows(
        "INSERT INTO places(user_id,name,source,latitude,longitude,created_at,updated_at) VALUES($1,'Suggested place',1,0,0,now(),now()) RETURNING id",
        [user]
      )

    id
  end
end
