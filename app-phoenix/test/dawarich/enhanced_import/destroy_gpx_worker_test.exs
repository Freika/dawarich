defmodule Dawarich.EnhancedImport.DestroyGpxWorkerTest do
  use Dawarich.EnhancedImportCase

  alias Dawarich.EnhancedImport.DestroyGpxWorker

  defp job(import_id),
    do: %Oban.Job{args: %{"import_id" => import_id, "event_id" => Ecto.UUID.generate()}}

  defp undo_fixture! do
    fixture = load!("undo_keeps_visited_place")
    [import] = fixture["input"]["imports"]
    {import["id"], fixture}
  end

  test "decodes only the v1 payload" do
    assert DestroyGpxWorker.args_from_command(1, %{"import_id" => 5}) ==
             {:ok, %{"import_id" => 5}}

    assert DestroyGpxWorker.args_from_command(1, %{"import_id" => "5"}) ==
             {:error, "invalid_payload"}

    assert DestroyGpxWorker.args_from_command(2, %{"import_id" => 5}) ==
             {:error, "unsupported_version"}
  end

  test "removes unreferenced extracted places with their joins" do
    {id, fixture} = undo_fixture!()
    expected = fixture["expected"]

    assert DestroyGpxWorker.run(ScratchRepo, job(id)) == :ok

    assert places() == expected_places(expected)
    assert tags() == expected_tags(expected)
    assert taggings() == []
    assert rows("SELECT count(*) FROM place_visits") == [[length(expected["place_visits"])]]
    assert rows("SELECT count(*) FROM notes") == [[length(expected["notes"])]]

    assert rows("SELECT id, place_id FROM visits ORDER BY id") ==
             Enum.map(expected["visits"], &[&1["id"], &1["place_id"]])

    assert import_state(id) == {0, %{}, nil}
    assert kinds() == expected["effects"]["kinds"]
    assert DestroyGpxWorker.run(ScratchRepo, job(id + 1)) == :ok
  end

  test "batches of 500" do
    [[user_id]] =
      rows(
        "INSERT INTO users (email, encrypted_password, created_at, updated_at) " <>
          "VALUES ('batch@example.test', '', now(), now()) RETURNING id"
      )

    [[import_id]] =
      rows(
        "INSERT INTO imports (user_id, name, source, created_at, updated_at) VALUES ($1, 'b.gpx', 4, now(), now()) RETURNING id",
        [user_id]
      )

    rows(
      "INSERT INTO places (user_id, import_id, name, latitude, longitude, lonlat, source, created_at, updated_at) " <>
        "SELECT $1, $2, 'P' || n, 51.3397, 12.3731, ST_SetSRID(ST_MakePoint(12.3731, 51.3397), 4326)::geography, " <>
        "2, now(), now() FROM generate_series(1, 1001) n",
      [user_id, import_id]
    )

    HookRepo.set_hook(fn sql, [ids | _] ->
      if sql =~ "DELETE FROM places" do
        [[txid]] = rows("SELECT txid_current()")
        send(self(), {:batch, length(ids), txid})
      end

      :ok
    end)

    assert DestroyGpxWorker.run(HookRepo, job(import_id)) == :ok

    batches =
      for _ <- 1..3 do
        assert_received {:batch, size, txid}
        {size, txid}
      end

    refute_received {:batch, _, _}
    assert Enum.map(batches, &elem(&1, 0)) == [500, 500, 1]
    assert batches |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 3
    assert rows("SELECT count(*) FROM places") == [[0]]
  end

  test "a failure writes Rails' message and re-raises" do
    {id, fixture} = undo_fixture!()

    HookRepo.set_hook(fn sql, _params ->
      if sql =~ "DELETE FROM places", do: raise("boom")
      :ok
    end)

    assert_raise RuntimeError, "boom", fn -> DestroyGpxWorker.run(HookRepo, job(id)) end

    assert {4,
            %{
              "error_message" => "Removing extracted data failed: boom",
              "counts" => %{"places" => 2}
            }, _} =
             import_state(id)

    assert Enum.map(kinds(), & &1["kind"]) == ["enhanced_import_card"]
    assert rows("SELECT count(*) FROM places") == [[2]]

    HookRepo.clear_hook()
    [visit | _] = fixture["input"]["visits"]
    rows("UPDATE visits SET import_id = $1 WHERE id = $2", [id, visit["id"]])

    assert_raise RuntimeError, "extracted visits or tracks present", fn ->
      DestroyGpxWorker.run(HookRepo, job(id))
    end

    assert {4,
            %{
              "error_message" =>
                "Removing extracted data failed: extracted visits or tracks present"
            }, _} =
             import_state(id)
  end
end
