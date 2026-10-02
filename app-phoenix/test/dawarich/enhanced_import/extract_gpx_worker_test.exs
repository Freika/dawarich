defmodule Dawarich.EnhancedImport.ExtractGpxWorkerTest do
  use Dawarich.EnhancedImportCase

  alias Dawarich.EnhancedImport.{Extract, ExtractGpxWorker}
  alias Dawarich.Tracks.PerUserLock

  @extracted ~w(decimal_cast_waypoint name_over_limit tag_reuse_and_privacy writer_dedup zipped_single_entry)
  @statuses %{
    0 => "not_attempted",
    1 => "pending",
    2 => "running",
    3 => "completed",
    4 => "failed"
  }

  defp job(import_id, overrides \\ []) do
    struct!(
      %Oban.Job{
        args: %{"import_id" => import_id, "lock_attempt" => 1, "event_id" => Ecto.UUID.generate()},
        attempt: 1,
        max_attempts: 3,
        meta: %{}
      },
      overrides
    )
  end

  defp run(repo, job, storage, opts \\ []),
    do: ExtractGpxWorker.run(repo, job, [storage: storage, lock: [timeout_ms: 200]] ++ opts)

  defp prepare!(storage, name) do
    fixture = load!(name)
    Enum.each(fixture["files"], &attach!(storage, &1))
    [import] = fixture["input"]["imports"]
    {import["id"], import["user_id"], fixture}
  end

  defp record_cards(import_id, raise_on_insert \\ nil) do
    HookRepo.set_hook(fn sql, params ->
      if sql =~ "INSERT INTO phoenix.rails_commands" and hd(params) == "enhanced_import_card" do
        [[status, payload]] =
          rows(
            "SELECT additional_data_extraction_status, additional_data_extraction FROM imports WHERE id = $1",
            [import_id]
          )

        send(self(), {:write, @statuses[status], payload["started_at"]})
      end

      if raise_on_insert && sql =~ "INSERT INTO places", do: raise(raise_on_insert)
      :ok
    end)
  end

  defp writes do
    receive do
      {:write, status, started_at} -> [{status, started_at} | writes()]
    after
      0 -> []
    end
  end

  defp kind_names, do: Enum.map(kinds(), & &1["kind"])

  test "decodes only the v1 payload" do
    assert ExtractGpxWorker.args_from_command(1, %{"import_id" => 5, "lock_attempt" => 2}) ==
             {:ok, %{"import_id" => 5, "lock_attempt" => 2}}

    assert ExtractGpxWorker.args_from_command(1, %{"import_id" => 5, "lock_attempt" => 0}) ==
             {:error, "invalid_payload"}

    assert ExtractGpxWorker.args_from_command(2, %{"import_id" => 5, "lock_attempt" => 1}) ==
             {:error, "unsupported_version"}
  end

  test "completes with counts, card and untracked kinds", %{storage: storage} do
    for name <- @extracted do
      truncate!()
      {id, _user_id, fixture} = prepare!(storage, name)
      expected = fixture["expected"]
      record_cards(id)

      assert run(HookRepo, job(id), storage) == :ok

      {status, payload, raw} = import_state(id)
      assert status == expected["import"]["additional_data_extraction_status"], name
      assert Map.keys(payload) == ~w(completed_at counts error_message started_at), name
      assert stamp?(payload["started_at"]) and stamp?(payload["completed_at"]), name
      assert payload["counts"] == expected["import"]["additional_data_extraction"]["counts"], name
      assert payload["error_message"] == nil, name
      assert raw == expected["import"]["raw_data"], name
      assert places() == expected_places(expected), name
      assert tags() == expected_tags(expected), name
      assert taggings() == expected_taggings(expected), name
      assert kinds() == expected["effects"]["kinds"], name
      assert Enum.map(writes(), &elem(&1, 0)) == expected["effects"]["card_statuses"], name
    end
  end

  test "extracts in chunks of 500 with one external-id lookup per chunk", %{storage: storage} do
    waypoints =
      for i <- 0..499,
          do:
            ~s(<wpt lat="#{51.2 + div(i, 25) * 0.001}" lon="#{12.3 + rem(i, 25) * 0.001}"><name>P#{i}</name></wpt>)

    xml = "<gpx>" <> Enum.join(waypoints ++ [hd(waypoints)]) <> "</gpx>"

    attach!(storage, %{
      "import_id" => 9,
      "filename" => "chunks.gpx",
      "content_type" => "application/gpx+xml",
      "byte_size" => byte_size(xml),
      "checksum" => Base.encode64(:crypto.hash(:md5, xml)),
      "base64" => Base.encode64(xml)
    })

    caller = self()

    HookRepo.set_hook(fn sql, _params ->
      if sql =~ "geodata ->> 'external_place_id' =", do: send(caller, :lookup)
      :ok
    end)

    deadline = %{at: System.monotonic_time(:millisecond) + 60_000, minutes: 1}
    import = %{id: 9, user_id: 1, raw_data: nil}

    assert Extract.process(HookRepo, import, storage, "chunks", deadline) == %{"places" => 501}
    assert rows("SELECT count(*) FROM places") == [[500]]
    assert lookups() == 2
  end

  defp lookups do
    receive do
      :lookup -> 1 + lookups()
    after
      0 -> 0
    end
  end

  test "a missing or non-GPX import does nothing", %{storage: storage} do
    [[id]] =
      rows(
        "INSERT INTO imports (user_id, name, source, created_at, updated_at) VALUES (1, 'a.json', 3, now(), now()) RETURNING id"
      )

    assert run(ScratchRepo, job(id), storage) == :ok
    assert run(ScratchRepo, job(id + 1), storage) == :ok
    assert import_state(id) == {0, %{}, nil}
    assert kinds() == []
  end

  test "no waypoints skips the download", %{storage: storage} do
    fixture = load!("waypoints_seen_zero")
    [import] = fixture["input"]["imports"]

    assert run(ScratchRepo, job(import["id"]), storage) == :ok

    {status, payload, _raw} = import_state(import["id"])
    assert status == 3
    assert payload["counts"] == %{}
    assert kinds() == fixture["expected"]["effects"]["kinds"]
    refute File.exists?(Path.join(storage.root, ".phoenix-tmp"))
  end

  test "a held lock snoozes and the 60th attempt fails", %{storage: storage} do
    {id, user_id, _fixture} = prepare!(storage, "writer_dedup")
    Redix.command!(rails_redis!(), ["SET", PerUserLock.key(user_id), "rails", "PX", "60000"])

    assert run(ScratchRepo, job(id), storage) == {:snooze, 60}
    assert {1, %{"started_at" => started_at}, _} = import_state(id)
    assert stamp?(started_at)
    assert kind_names() == ["enhanced_import_card"]

    assert run(ScratchRepo, job(id, meta: %{"snoozed" => 59}), storage) == :ok

    assert {4, %{"error_message" => message}, _} = import_state(id)

    assert message ==
             "Tracks::PerUserLock: could not acquire lock for user_id=#{user_id} within 30.0s"

    assert kind_names() ==
             ~w(enhanced_import_card enhanced_import_card enhanced_import_card schedule_untracked_tracks)

    assert rows("SELECT count(*) FROM places WHERE import_id = $1", [id]) == [[0]]
  end

  test "an error retries, and the final attempt fails", %{storage: storage} do
    {id, _user_id, _fixture} = prepare!(storage, "writer_dedup")
    record_cards(id, RuntimeError.exception("writer boom"))

    assert_raise RuntimeError, "writer boom", fn -> run(HookRepo, job(id), storage) end
    assert {1, %{"error_message" => "writer boom"}, _} = import_state(id)
    assert [{"running", _}, {"pending", _}] = writes()

    rows("TRUNCATE phoenix.rails_commands")

    assert_raise RuntimeError, "writer boom", fn ->
      run(HookRepo, job(id, attempt: 3), storage)
    end

    assert [{"running", _}, {"pending", retried_at}, {"failed", retried_at}] = writes()

    assert {4, %{"error_message" => "writer boom", "started_at" => ^retried_at}, _} =
             import_state(id)

    assert kind_names() ==
             ~w(enhanced_import_card enhanced_import_card enhanced_import_card schedule_untracked_tracks)
  end

  test "a deadlock writes no retrying state", %{storage: storage} do
    {id, _user_id, _fixture} = prepare!(storage, "writer_dedup")

    deadlock =
      Postgrex.Error.exception(
        postgres: %{code: "40P01", severity: "ERROR", message: "deadlock detected"}
      )

    record_cards(id, deadlock)

    assert_raise Postgrex.Error, fn -> run(HookRepo, job(id), storage) end
    assert {2, %{"error_message" => nil}, _} = import_state(id)
    assert [{"running", _}] = writes()

    assert_raise Postgrex.Error, fn -> run(HookRepo, job(id, attempt: 3), storage) end

    assert {4, %{"error_message" => "ERROR 40P01 (deadlock_detected) deadlock detected"}, _} =
             import_state(id)

    assert [{"running", _}, {"failed", _}] = writes()
    assert List.last(kind_names()) == "schedule_untracked_tracks"
  end

  test "a run past its deadline fails the final attempt", %{storage: storage} do
    {id, user_id, _fixture} = prepare!(storage, "writer_dedup")
    previous = Application.fetch_env!(:dawarich, :extraction_timeout_ms)
    Application.put_env(:dawarich, :extraction_timeout_ms, 60_000)
    on_exit(fn -> Application.put_env(:dawarich, :extraction_timeout_ms, previous) end)

    assert_raise RuntimeError, ~r/\AGPX extraction did not finish within/, fn ->
      run(ScratchRepo, job(id, attempt: 3), storage)
    end

    assert {4, %{"error_message" => "GPX extraction did not finish within " <> _}, _} =
             import_state(id)

    assert List.last(kind_names()) == "schedule_untracked_tracks"
    assert rows("SELECT count(*) FROM places WHERE import_id = $1", [id]) == [[0]]
    assert Redix.command!(rails_redis!(), ["GET", PerUserLock.key(user_id)]) == nil
  end

  defp rails_redis! do
    config = Application.fetch_env!(:dawarich, :redis)
    {:ok, conn} = Redix.start_link(config[:url], database: config[:database])
    conn
  end
end
