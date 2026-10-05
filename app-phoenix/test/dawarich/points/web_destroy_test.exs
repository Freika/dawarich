defmodule Dawarich.Points.WebDestroyTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Points.WebDestroy
  alias Dawarich.Test.{FrameSeeds, RailsUser}

  defmodule IntentFailureRepo do
    defdelegate transaction(fun), to: Dawarich.Repo
    defdelegate rollback(reason), to: Dawarich.Repo

    def query!(sql, params, opts \\ []) do
      if String.starts_with?(sql, "INSERT INTO phoenix.rails_commands"),
        do: raise("synthetic follow-up failure"),
        else: Dawarich.Repo.query!(sql, params, opts)
    end
  end

  setup do
    user =
      RailsUser.insert!(%{
        id: 91981,
        email: "a6s4-point-writes@example.invalid",
        plan: 0,
        points_count: 3,
        settings: %{"timezone" => "Europe/Berlin"}
      })

    foreign =
      RailsUser.insert!(%{
        id: 91982,
        email: "a6s4-point-writes-foreign@example.invalid",
        points_count: 1
      })

    Repo.insert_all("imports", [
      %{
        id: 919_810,
        user_id: user.id,
        name: "Synthetic.json",
        points_count: 3,
        created_at: ~N[2026-10-02 10:00:00],
        updated_at: ~N[2026-10-02 10:00:00]
      }
    ])

    FrameSeeds.track!(user.id, 919_810, %{
      start_at: ~N[2025-12-31 23:30:00],
      end_at: ~N[2026-01-01 00:15:00]
    })

    for {actor, id, stamp} <- [
          {user, 919_810, 1_767_223_800},
          {user, 919_811, 1_767_224_700},
          {user, 919_812, 1_767_226_500},
          {foreign, 919_819, 1_791_021_600}
        ] do
      FrameSeeds.point!(actor.id, id, stamp)

      if actor == user,
        do:
          Repo.query!(
            "UPDATE points SET import_id=919810,track_id=919810,raw_data=$2 WHERE id=$1",
            [id, %{"synthetic" => true}]
          )
    end

    %{user: user, ctx: %{locale: "de", timezone: "Europe/Berlin"}}
  end

  defp state do
    for table <- ~w(points users imports tracks),
        do: Repo.query!("SELECT to_jsonb(t)::text FROM #{table} t ORDER BY id").rows
  end

  test "mixed duplicate foreign Lite-old selection deletes actor rows once", ctx do
    assert {:ok, %{deleted: deleted, selected: true}} =
             WebDestroy.run(Repo, ctx.user, ["", "919810", "919810", "919819", "919811"], ctx.ctx)

    assert Enum.map(deleted, & &1.id) == [919_810, 919_811]
    assert Repo.query!("SELECT id FROM points ORDER BY id").rows == [[919_812], [919_819]]
    assert [["points.web_destroy_follow_up", payload]] = commands()
    assert payload["timestamps"] == [1_767_223_800, 1_767_224_700]
    assert payload["track_ids"] == [919_810]
    assert payload["oldest_timestamp"] == 1_767_223_800
    assert payload["timezone"] == "Europe/Berlin"
    assert payload["locale"] == "de"
  end

  test "deleted points and follow-up timestamps use ascending ids despite descending insertion",
       ctx do
    Repo.query!("DELETE FROM points WHERE id IN (919810,919811)")
    FrameSeeds.point!(ctx.user.id, 919_811, 1_767_224_700)
    FrameSeeds.point!(ctx.user.id, 919_810, 1_767_223_800)
    Repo.query!("SET LOCAL enable_indexscan=off")
    Repo.query!("SET LOCAL enable_bitmapscan=off")

    assert {:ok, %{deleted: deleted}} =
             WebDestroy.run(Repo, ctx.user, ["919811", "919810"], ctx.ctx)

    assert Enum.map(deleted, & &1.id) == [919_810, 919_811]
    assert [["points.web_destroy_follow_up", payload]] = commands()
    assert payload["timestamps"] == [1_767_223_800, 1_767_224_700]
  end

  test "actual deleted rows adjust user import counters preserve archives", ctx do
    stamp = ~N[2026-10-02 10:00:00]

    Repo.insert_all("points_raw_data_archives", [
      %{
        id: 919_810,
        user_id: ctx.user.id,
        archived_at: stamp,
        created_at: stamp,
        updated_at: stamp,
        month: 12,
        year: 2025,
        point_count: 2,
        point_ids_checksum: "synthetic-checksum"
      }
    ])

    Repo.query!(
      "UPDATE points SET raw_data_archive_id=919810,raw_data_archived=true WHERE id IN (919810,919812)"
    )

    archives =
      Repo.query!("SELECT to_jsonb(a)::text FROM points_raw_data_archives a ORDER BY id").rows

    before = Repo.query!("SELECT updated_at FROM users WHERE id=91981").rows
    tracks = Repo.query!("SELECT to_jsonb(t)::text FROM tracks t").rows
    survivor = Repo.query!("SELECT raw_data,raw_data_archive_id FROM points WHERE id=919812").rows
    assert {:ok, _} = WebDestroy.run(Repo, ctx.user, ["919810", "919811"], ctx.ctx)
    assert Repo.query!("SELECT points_count FROM users ORDER BY id").rows == [[1], [1]]

    assert Repo.query!("SELECT points_count,updated_at FROM imports WHERE id=919810").rows == [
             [1, ~N[2026-10-02 10:00:00.000000]]
           ]

    assert Repo.query!("SELECT updated_at FROM users WHERE id=91981").rows == before
    assert Repo.query!("SELECT to_jsonb(t)::text FROM tracks t").rows == tracks

    assert Repo.query!("SELECT raw_data,raw_data_archive_id FROM points WHERE id=919812").rows ==
             survivor

    assert Repo.query!("SELECT to_jsonb(a)::text FROM points_raw_data_archives a ORDER BY id").rows ==
             archives
  end

  test "empty unmatched selection changes no counters effects", ctx do
    before = state()

    for {ids, selected} <- [
          {nil, false},
          {["", " ", "　"], false},
          {["919818"], true},
          {["919819"], true}
        ] do
      assert {:ok, %{deleted: [], selected: ^selected}} =
               WebDestroy.run(Repo, ctx.user, ids, ctx.ctx)

      assert state() == before
      assert commands() == []
    end
  end

  test "effect-intent failure rolls back deletion counters row versions", ctx do
    before = state()
    assert :rails = WebDestroy.run(IntentFailureRepo, ctx.user, ["919810"], ctx.ctx)
    assert state() == before
    assert commands() == []

    assert :rails =
             WebDestroy.run(
               Repo,
               ctx.user,
               ["919810"],
               Map.put(ctx.ctx, :render, fn _ -> :rails end)
             )

    assert state() == before
  end
end
