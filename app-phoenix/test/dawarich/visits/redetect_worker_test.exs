defmodule Dawarich.Visits.RedetectWorkerTest do
  use Dawarich.VisitsCase, async: false

  alias Dawarich.Geocoding.HookRepo
  alias Dawarich.Tracks.PerUserLock
  alias Dawarich.Visits.RedetectWorker

  @oban __MODULE__.Oban
  @worker "Dawarich.Visits.RedetectWorker"

  setup do
    start_oban(@oban)
    :ok
  end

  test "cooldown, busy and no points" do
    cooled = user!(9101)

    rows("UPDATE users SET visits_redetected_at = now() - interval '10 minutes' WHERE id = $1", [
      cooled
    ])

    assert RedetectWorker.perform(job(start_args(cooled))) == :ok
    assert notifications(cooled) == []
    assert lease_holders(ScratchRepo, run_key(cooled)) == []

    busy = user!(9102)
    hold_lease!(ScratchRepo, run_key(busy), "other-token")
    assert RedetectWorker.perform(job(start_args(busy))) == :ok

    assert notifications(busy) == [
             %{
               "kind" => 1,
               "title" => "Visit re-detection busy",
               "content" => "Another re-detection is already running. Try again in a few minutes."
             }
           ]

    assert lease_holders(ScratchRepo, run_key(busy)) == [["other-token"]]

    empty = user!(9103)
    assert RedetectWorker.perform(job(start_args(empty))) == :ok

    assert notifications(empty) == [
             %{
               "kind" => 0,
               "title" => "Visit re-detection",
               "content" => "No points to re-detect."
             }
           ]

    assert lease_holders(ScratchRepo, run_key(empty)) == []
  end

  test "three months chain to a complete notification" do
    for name <- ["full_history_redetect", "full_history_redetect_pl"] do
      f = load_visits!(name)
      uid = user_id(f)
      args = start_args(uid, %{"time_zone" => f["time_zone"]})

      assert RedetectWorker.perform(job(args)) == :ok
      results = run_months(args["event_id"])

      assert results == List.duplicate(:ok, length(f["months"]))
      assert notifications(uid) == f["expected"]["notifications"]

      assert rows("SELECT visits_redetected_at IS NOT NULL FROM users WHERE id = $1", [uid]) == [
               [true]
             ]

      assert length(visits(uid)) == length(f["expected"]["visits"])
    end
  end

  test "a failed month gives a partial notification and no cooldown" do
    f = load_visits!("full_history_redetect_partial")
    uid = user_id(f)
    [failing_start, _] = Enum.at(f["months"], f["failing_month"])

    HookRepo.set_hook(fn _sql, params ->
      if match?([_, ^failing_start, _], params), do: raise("forced month failure")
    end)

    use_repo!(HookRepo)
    args = start_args(uid, %{"time_zone" => f["time_zone"]})

    assert RedetectWorker.perform(job(args)) == :ok
    results = run_months(args["event_id"])

    assert results == List.duplicate(:ok, length(f["months"]))
    assert notifications(uid) == f["expected"]["notifications"]
    assert rows("SELECT visits_redetected_at FROM users WHERE id = $1", [uid]) == [[nil]]
  end

  test "a month lock timeout snoozes" do
    uid = user!(9110)
    point!(uid, 1_790_000_000)
    event_id = Ecto.UUID.generate()
    hold_lease!(ScratchRepo, PerUserLock.key(uid), "someone-else")
    hold_lease!(ScratchRepo, run_key(uid), event_id)

    args = month_args(uid, event_id, 0, 1)

    assert RedetectWorker.perform(job(args)) == {:snooze, 30}
    assert visits(uid) == []
    assert lease_holders(ScratchRepo, run_key(uid)) == [[event_id]]
  end

  test "a superseded run stops" do
    uid = user!(9111)
    point!(uid, 1_790_000_000)
    event_id = Ecto.UUID.generate()
    hold_lease!(ScratchRepo, run_key(uid), "someone-else")
    args = month_args(uid, event_id, 0, 1)

    assert RedetectWorker.perform(job(args)) == :ok
    assert visits(uid) == []
    assert notifications(uid) == []
  end

  test "a handled exception cancels, notifies and releases" do
    uid = user!(9112)
    point!(uid, 1_790_000_000)
    event_id = Ecto.UUID.generate()
    hold_lease!(ScratchRepo, run_key(uid), event_id)
    args = month_args(uid, event_id, 0, 2)
    the_job = job(args)
    stop_supervised!(@oban)

    assert {:cancel, message} = RedetectWorker.perform(the_job)
    assert is_binary(message) and message != ""

    assert [%{"kind" => 2, "title" => "Visit re-detection failed", "content" => content}] =
             notifications(uid)

    assert content == message
    assert lease_holders(ScratchRepo, run_key(uid)) == []
  end

  test "a database error on renew raises so Oban retries the month, and the run keeps its lease" do
    uid = user!(9113)
    event_id = Ecto.UUID.generate()
    hold_lease!(ScratchRepo, run_key(uid), event_id)
    args = month_args(uid, event_id, 0, 1)

    HookRepo.set_hook(fn sql, _params ->
      if String.starts_with?(sql, "UPDATE phoenix.leases"),
        do: raise(DBConnection.ConnectionError, "connection dropped")
    end)

    use_repo!(HookRepo)

    assert_raise DBConnection.ConnectionError, fn -> RedetectWorker.perform(job(args)) end
    assert lease_holders(ScratchRepo, run_key(uid)) == [[event_id]]
    assert notifications(uid) == []
  end

  test "priorities" do
    month = month_args(1, "e", 0, 1)

    assert RedetectWorker.new(start_args(1)).changes.priority == 3
    assert RedetectWorker.new(month).changes.priority == 3
    assert RedetectWorker.new(start_args(1)).changes.max_attempts == 1
    assert RedetectWorker.new(month).changes.max_attempts == 3
  end

  test "decoders" do
    valid = %{"user_id" => 1, "time_zone" => "Europe/Berlin", "plan_restricted" => false}
    assert RedetectWorker.args_from_command(1, valid) == {:ok, Map.put(valid, "step", "start")}

    for payload <- [
          Map.put(valid, "extra", 1),
          %{valid | "user_id" => "1"},
          %{valid | "plan_restricted" => "false"},
          Map.delete(valid, "time_zone")
        ] do
      assert RedetectWorker.args_from_command(1, payload) == {:error, "invalid_payload"}
    end

    assert RedetectWorker.args_from_command(2, valid) == {:error, "unsupported_version"}
  end

  defp user!(id) do
    Wave5bFixtures.load_input!(ScratchRepo, %{"users" => [%{"id" => id}]})
    id
  end

  defp point!(uid, ts),
    do:
      rows(
        "INSERT INTO points (user_id, timestamp, lonlat, accuracy, created_at, updated_at) " <>
          "VALUES ($1, $2, ST_GeomFromText('POINT(12.3731 51.3397)', 4326)::geography, 10, now(), now())",
        [uid, ts]
      )

  defp job(args), do: %Oban.Job{args: args, conf: Oban.config(@oban)}

  defp start_args(uid, overrides \\ %{}),
    do:
      Map.merge(
        %{
          "event_id" => Ecto.UUID.generate(),
          "user_id" => uid,
          "time_zone" => "UTC",
          "plan_restricted" => false,
          "step" => "start"
        },
        overrides
      )

  defp month_args(uid, event_id, step, months_total) do
    %{
      "user_id" => uid,
      "event_id" => event_id,
      "time_zone" => "UTC",
      "plan_restricted" => false,
      "step" => step,
      "min_ts" => 1_789_000_000,
      "max_ts" => 1_791_000_000,
      "months_total" => months_total,
      "visits_created" => 0,
      "months_failed" => 0
    }
  end

  defp run_key(uid), do: "visits:redetect_run:#{uid}"

  defp notifications(uid) do
    for [kind, title, content] <-
          rows("SELECT kind, title, content FROM notifications WHERE user_id = $1 ORDER BY id", [
            uid
          ]),
        do: %{"kind" => kind, "title" => title, "content" => content}
  end

  defp run_months(event_id) do
    case rows(
           "SELECT args FROM oban.oban_jobs WHERE worker = $1 AND args->>'event_id' = $2 " <>
             "ORDER BY id DESC LIMIT 1",
           [@worker, event_id]
         ) do
      [[next_args]] ->
        ScratchRepo.query!("DELETE FROM oban.oban_jobs WHERE worker = $1", [@worker])
        [RedetectWorker.perform(job(next_args)) | run_months(event_id)]

      [] ->
        []
    end
  end

  defp use_repo!(repo) do
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)
  end
end
