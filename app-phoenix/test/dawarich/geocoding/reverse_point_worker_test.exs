defmodule Dawarich.Geocoding.ReversePointWorkerTest do
  use Dawarich.GeocodingCase, async: false

  alias Dawarich.Geocoding.ReversePointWorker
  alias Dawarich.Redis

  @oban __MODULE__.Oban
  @load "SELECT id, user_id, timestamp"

  setup do
    start_oban(@oban)
    :ok
  end

  test "a batch geocodes each point and releases each key" do
    f = load!("point_batch")
    stub_requests!(f["requests"])
    ids = [6207, 6208, 6209]
    set_keys!(ids)

    assert ReversePointWorker.perform(job(f, ids, false)) == :ok

    assert length(FakeHttp.requests()) == 3
    assert for([id, "Leipzig", _, _, _, true, 1] <- points(), do: id) == ids
    assert length(kinds()) == 3 and Enum.all?(kinds(), &(&1["kind"] == "points.tile_epoch"))
    refute Enum.any?(ids, &dedupe_key?/1)
  end

  test "the point_batch fixture replays Rails' rows, effects and keys" do
    f = load!("point_batch")
    stub_requests!(f["requests"])
    set_keys!(for {id, true} <- f["dedupe_keys"]["before"], do: String.to_integer(id))

    ExUnit.CaptureLog.capture_log(fn ->
      for {force, calls} <- Enum.group_by(f["calls"], & &1["force"]) do
        assert ReversePointWorker.perform(job(f, Enum.map(calls, & &1["point_id"]), force)) == :ok
      end
    end)

    assert points() == expected_points(f["expected"]["points"])

    assert Enum.sort_by(kinds(), & &1["payload"]["timestamps"]) ==
             f["expected"]["effects"]["kinds"]

    assert geocoded_days() == f["expected"]["effects"]["geocoded_days"]

    assert Map.new(f["dedupe_keys"]["after"], fn {id, _} -> {id, dedupe_key?(id)} end) ==
             f["dedupe_keys"]["after"]
  end

  test "one failing point does not fail the batch" do
    f = load!("point_batch")
    stub_requests!(f["requests"])
    ids = [6207, 6208, 6209]
    set_keys!(ids)
    FakeHttp.stub_raise(Enum.at(f["requests"], 1)["url"])

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert ReversePointWorker.perform(job(f, ids, false)) == :ok
      end)

    assert log =~ "event=geocoding.point_error point_id=6208 class=RuntimeError"

    assert [
             [6207, "Leipzig" | _],
             [6208, nil, nil, nil, "{}", false, 0],
             [6209, "Leipzig" | _] | _
           ] = points()

    refute Enum.any?(ids, &dedupe_key?/1)
  end

  test "a database error on load fails the job" do
    f = load!("point_batch")
    stub_requests!(f["requests"])
    ids = [6207, 6208, 6209]
    failures = :atomics.new(1, [])

    HookRepo.set_hook(fn sql, params ->
      if String.starts_with?(sql, @load) and params == [6208] and
           :atomics.add_get(failures, 1, 1) == 1,
         do: raise(DBConnection.ConnectionError, "connection dropped")

      :ok
    end)

    use_repo!(HookRepo)
    job = job(f, ids, false)

    assert_raise DBConnection.ConnectionError, fn -> ReversePointWorker.perform(job) end
    assert [[6207, "Leipzig", _, _, _, true, 1], [6208, nil | _] | _] = points()

    assert ReversePointWorker.perform(job) == :ok
    assert for([id, "Leipzig", _, _, _, true, 1] <- points(), do: id) == ids
    assert FakeHttp.requests() == f["requests"] |> Enum.take(3) |> Enum.map(& &1["url"])
  end

  test "a spent budget continues at the next index" do
    f = load!("point_batch")
    stub_requests!(f["requests"])
    Application.put_env(:dawarich, :geocoding_batch_budget_ms, 0)
    on_exit(fn -> Application.delete_env(:dawarich, :geocoding_batch_budget_ms) end)
    first = job(f, [6207, 6208, 6209], false)

    assert ReversePointWorker.perform(first) == :ok
    assert geocoded() == [6207]
    assert continuations() == [Map.put(first.args, "cursor", 1)]

    assert ReversePointWorker.perform(%{first | args: Map.put(first.args, "cursor", 1)}) == :ok
    assert geocoded() == [6207, 6208]
    assert continuations() == [Map.put(first.args, "cursor", 1), Map.put(first.args, "cursor", 2)]

    assert ReversePointWorker.perform(first) == :ok
    assert length(continuations()) == 2
  end

  test "releases the dedupe key unless force" do
    f = load!("point_batch")
    stub_requests!(f["requests"])
    set_keys!([6207, 6211])

    assert ReversePointWorker.perform(job(f, [6207], false)) == :ok
    assert ReversePointWorker.perform(job(f, [6211], true)) == :ok
    refute dedupe_key?(6207)
    assert dedupe_key?(6211)

    ScratchRepo.query!("TRUNCATE points, instance_settings RESTART IDENTITY CASCADE", [],
      log: false
    )

    disabled = load!("point_job_disabled")
    [%{"point_id" => id}] = disabled["calls"]
    set_keys!([id])
    requests = FakeHttp.requests()

    assert ReversePointWorker.perform(job(disabled, [id], false)) == :ok
    assert FakeHttp.requests() == requests
    refute dedupe_key?(id)
    assert points() == expected_points(disabled["expected"]["points"])
  end

  test "decoders" do
    valid = %{"user_id" => 1, "point_ids" => [1, 2], "force" => false}

    assert ReversePointWorker.args_from_command(1, valid) == {:ok, Map.put(valid, "cursor", 0)}

    for payload <- [
          Map.put(valid, "extra", 1),
          %{valid | "user_id" => "1"},
          %{valid | "point_ids" => []},
          %{valid | "point_ids" => Enum.to_list(1..101)},
          %{valid | "point_ids" => [1, "2"]},
          %{valid | "force" => "false"},
          Map.delete(valid, "force")
        ] do
      assert ReversePointWorker.args_from_command(1, payload) == {:error, "invalid_payload"}
    end

    assert ReversePointWorker.args_from_command(1, %{valid | "point_ids" => Enum.to_list(1..100)}) ==
             {:ok, %{valid | "point_ids" => Enum.to_list(1..100)} |> Map.put("cursor", 0)}

    assert ReversePointWorker.args_from_command(2, valid) == {:error, "unsupported_version"}
  end

  test "queue, attempts, timeout and uniqueness" do
    changeset = ReversePointWorker.new(%{"event_id" => "e", "cursor" => 0})
    assert changeset.changes.queue == "reverse_geocoding"
    assert changeset.changes.max_attempts == 4
    assert changeset.changes.unique.keys == [:event_id, :cursor]
    assert changeset.changes.unique.period == :infinity
    assert ReversePointWorker.timeout(%Oban.Job{}) == :timer.minutes(15)
  end

  defp job(f, ids, force) do
    [user] = f["input"]["users"]

    args = %{
      "event_id" => Ecto.UUID.generate(),
      "user_id" => user["id"],
      "point_ids" => ids,
      "force" => force,
      "cursor" => 0
    }

    %Oban.Job{args: args, conf: Oban.config(@oban), attempt: 1, max_attempts: 4}
  end

  defp set_keys!(ids),
    do: Enum.each(ids, &({:ok, "OK"} = Redis.command(["SET", dedupe_key(&1), "1"])))

  defp geocoded, do: for([id, _, _, _, _, true, _] <- points(), do: id)

  defp continuations do
    for [args] <-
          rows("SELECT args FROM oban.oban_jobs WHERE worker = $1 ORDER BY id", [
            "Dawarich.Geocoding.ReversePointWorker"
          ]),
        do: args
  end

  defp use_repo!(repo) do
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)
  end
end
