defmodule Dawarich.Tracks.PointsTest do
  use Dawarich.TracksCase

  alias Dawarich.Tracks.Points

  test "Q2 excludes held imports except in import-scoped chunks" do
    %{call: [daily, scoped]} = TracksFixtures.load!(ScratchRepo, "range_q2")
    input = TracksFixtures.read!("range_q2")["input"]["points"]

    [held] =
      for i <- TracksFixtures.read!("range_q2")["input"]["imports"], i["status"] == 1, do: i["id"]

    ids_where = fn keep? -> for p <- input, keep?.(p), do: p["id"] end

    daily_ids =
      ScratchRepo
      |> Points.load_chunk(1, daily["start_at"], daily["end_at"],
        untracked_only: false,
        import_id: nil
      )
      |> Enum.map(& &1.id)

    assert daily_ids == ids_where.(&(&1["import_id"] != held))
    assert Enum.any?(input, &(&1["import_id"] not in [nil, held]))

    scoped_ids =
      ScratchRepo
      |> Points.load_chunk(1, daily["start_at"], daily["end_at"],
        untracked_only: scoped["untracked_only"],
        import_id: held
      )
      |> Enum.map(& &1.id)

    assert scoped_ids == ids_where.(&(&1["import_id"] == held))
    assert scoped_ids != []
  end

  test "the orphan claim skips held imports unless the chunk is import-scoped" do
    TracksFixtures.load!(ScratchRepo, "range_q2")
    input = TracksFixtures.read!("range_q2")["input"]["points"]
    all_ids = Enum.map(input, & &1["id"])
    held_ids = for p <- input, p["import_id"] == 1, do: p["id"]

    {:ok, unscoped} =
      ScratchRepo.transaction(fn -> Points.claim_orphans!(ScratchRepo, 1, all_ids, false) end)

    {:ok, scoped} =
      ScratchRepo.transaction(fn -> Points.claim_orphans!(ScratchRepo, 1, all_ids, true) end)

    assert Enum.map(unscoped, & &1.id) == Enum.sort(all_ids -- held_ids)
    assert Enum.map(scoped, & &1.id) == Enum.sort(all_ids)
  end

  test "the orphan claim locks rows" do
    TracksFixtures.load!(ScratchRepo, "range_q2")
    [[id]] = rows("SELECT min(id) FROM points WHERE import_id IS NULL")
    parent = self()

    claim =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          send(parent, {:claimed, Points.claim_orphans!(ScratchRepo, 1, [id], false)})

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive {:claimed, [%{id: ^id}]}

    assert {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}} =
             ScratchRepo.query("SELECT id FROM points WHERE id = $1 FOR UPDATE NOWAIT", [id])

    send(claim.pid, :release)
    assert {:ok, :ok} = Task.await(claim)
  end

  test "an omitted untracked_only loads tracked points too, as Rails' nil does" do
    TracksFixtures.load!(ScratchRepo, "range_kept")
    tracked = for {id, track_id} <- point_track_ids(), track_id != nil, do: id

    loaded =
      ScratchRepo
      |> Points.load_chunk(1, 1_780_290_000, 1_780_308_000, import_id: nil)
      |> Enum.map(& &1.id)

    assert tracked != []
    assert Enum.sort(loaded) == Enum.sort(tracked)
  end
end
