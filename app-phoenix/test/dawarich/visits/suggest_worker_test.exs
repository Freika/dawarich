defmodule Dawarich.Visits.SuggestWorkerTest do
  use Dawarich.VisitsCase, async: false

  alias Dawarich.Geocoding.HookRepo
  alias Dawarich.Visits.{Suggest, SuggestWorker}

  @oban __MODULE__.Oban
  @worker "Dawarich.Visits.SuggestWorker"

  setup do
    start_oban(@oban)
    :ok
  end

  test "a calendar range runs Rails' chunks as a chain" do
    f = load_visits!("calendar_dst")
    uid = user_id(f)
    zone = f["calendar"]["time_zone"]

    for range <- f["calendar"]["ranges"] do
      ScratchRepo.query!("DELETE FROM oban.oban_jobs WHERE worker = $1", [@worker])

      chunks =
        drive_chain(
          uid,
          zone,
          "calendar",
          range["start_at"] |> local_epoch(zone),
          local_epoch(range["end_at"], zone)
        )

      assert chunks == range["chunks"]
    end

    assert job_count() == 0
  end

  test "fixed stepping" do
    f = load_visits!("calendar_dst")
    uid = user_id(f)
    fixed = f["fixed"]

    chunks = drive_chain(uid, "Europe/Berlin", "fixed", fixed["start_at"], fixed["end_at"])

    assert chunks == fixed["chunks"]
    for [a, b] <- chunks, b != fixed["end_at"], do: assert(b - a == 86_400)

    zone = f["calendar"]["time_zone"]
    dst_range = Enum.at(f["calendar"]["ranges"], 1)
    start_at = local_epoch(dst_range["start_at"], zone)
    end_at = local_epoch(dst_range["end_at"], zone)
    ScratchRepo.query!("DELETE FROM oban.oban_jobs WHERE worker = $1", [@worker])
    dst_chunks = drive_chain(uid, zone, "fixed", start_at, end_at)

    for [a, b] <- dst_chunks, b != end_at, do: assert(b - a == 86_400)
    assert job_count() == 0
  end

  test "a replayed chunk inserts no second successor" do
    f = load_visits!("calendar_dst")
    uid = user_id(f)
    t = 1_790_000_000
    args = fixed_args(uid, t, t + 172_800)
    conf = Oban.config(@oban)

    assert SuggestWorker.perform(%Oban.Job{args: args, conf: conf}) == :ok
    assert job_count() == 1

    assert SuggestWorker.perform(%Oban.Job{args: args, conf: conf}) == :ok
    assert job_count() == 1
  end

  test "an empty range does nothing" do
    f = load_visits!("calendar_dst")
    uid = user_id(f)
    t = 1_790_000_000
    args = fixed_args(uid, t, t)
    conf = Oban.config(@oban)

    calls =
      capture_known_calls(fn -> SuggestWorker.perform(%Oban.Job{args: args, conf: conf}) end)

    assert calls == []
    assert job_count() == 0
  end

  test "an exception notifies once per hour and still succeeds" do
    f = load_visits!("suggest_error_notification")
    uid = user_id(f)
    args = %{"time_zone" => "UTC", "plan_restricted" => false}

    HookRepo.set_hook(fn sql, _params ->
      if String.starts_with?(sql, "SELECT EXISTS (SELECT 1 FROM points"),
        do: raise(f["run"]["message"])
    end)

    assert Suggest.run(HookRepo, uid, f["run"]["start_at"], f["run"]["end_at"], args) == :ok
    assert notifications(uid) == f["expected"]["notifications"]

    assert rows(
             "SELECT expires_at - statement_timestamp() BETWEEN interval '3599 seconds' AND interval '3600 seconds' FROM phoenix.once_claims WHERE key = $1",
             ["visit_suggest_error:user:#{uid}"]
           ) == [[true]]

    assert Suggest.run(HookRepo, uid, f["run"]["start_at"], f["run"]["end_at"], args) == :ok
    assert length(notifications(uid)) == 1

    HookRepo.set_hook(fn sql, _params ->
      cond do
        String.starts_with?(sql, "SELECT EXISTS (SELECT 1 FROM points") ->
          raise(f["run"]["message"])

        String.starts_with?(sql, "INSERT INTO phoenix.once_claims") ->
          raise(DBConnection.ConnectionError, "connection dropped")

        true ->
          :ok
      end
    end)

    assert Suggest.run(HookRepo, uid, f["run"]["start_at"], f["run"]["end_at"], args) == :ok
    assert length(notifications(uid)) == 2
  end

  test "fresh visits request place geocoding once per place" do
    fresh = load_visits!("suggest_fresh_vs_covered")
    fresh_place_id = Enum.find(fresh["input"]["places"], &(&1["name"] == "Fresh Place"))["id"]

    assert Suggest.run(
             ScratchRepo,
             user_id(fresh),
             fresh["run"]["start_at"],
             fresh["run"]["end_at"],
             run_args(fresh)
           ) == :ok

    assert effects(actual_place_keys())["reverse_geocode_place_ids"] == [fresh_place_id]

    Dawarich.FixtureCleanup.delete!(
      ScratchRepo,
      ~w(users  points  visits  places  place_visits  tags  taggings  notes  phoenix.rails_commands  instance_settings)
    )

    disabled = load_visits!("suggest_geocoding_disabled")

    assert Suggest.run(
             ScratchRepo,
             user_id(disabled),
             disabled["run"]["start_at"],
             disabled["run"]["end_at"],
             run_args(disabled)
           ) == :ok

    assert effects(actual_place_keys())["reverse_geocode_place_ids"] == []
  end

  test "priorities" do
    assert SuggestWorker.new(fixed_args(1, 0, 86_400)).changes.priority == 1

    assert SuggestWorker.new(%{fixed_args(1, 0, 86_400) | "stepping" => "calendar"}).changes.priority ==
             0
  end

  test "decoders" do
    valid = %{
      "user_id" => 1,
      "start_at" => 0,
      "end_at" => 86_400,
      "stepping" => "calendar",
      "time_zone" => "Europe/Berlin",
      "plan_restricted" => false
    }

    expected = Map.put(valid, "cursor", 0)
    assert {:ok, ^expected} = SuggestWorker.args_from_command(1, valid)

    for payload <- [
          Map.put(valid, "extra", 1),
          %{valid | "user_id" => "1"},
          %{valid | "stepping" => "weekly"},
          %{valid | "plan_restricted" => "false"},
          Map.delete(valid, "time_zone")
        ] do
      assert SuggestWorker.args_from_command(1, payload) == {:error, "invalid_payload"}
    end

    assert SuggestWorker.args_from_command(2, valid) == {:error, "unsupported_version"}
  end

  defp drive_chain(uid, zone, stepping, start_at, end_at) do
    args = %{
      "event_id" => Ecto.UUID.generate(),
      "user_id" => uid,
      "start_at" => start_at,
      "end_at" => end_at,
      "stepping" => stepping,
      "time_zone" => zone,
      "plan_restricted" => false,
      "cursor" => start_at
    }

    calls = capture_known_calls(fn -> run_chain(args) end)
    for [_uid, stop, start] <- calls, do: [epoch(start), epoch(stop)]
  end

  defp run_chain(args) do
    conf = Oban.config(@oban)
    assert SuggestWorker.perform(%Oban.Job{args: args, conf: conf}) == :ok

    case rows("SELECT args FROM oban.oban_jobs WHERE worker = $1 ORDER BY id DESC LIMIT 1", [
           @worker
         ]) do
      [[next_args]] ->
        ScratchRepo.query!("DELETE FROM oban.oban_jobs WHERE worker = $1", [@worker])
        run_chain(next_args)

      [] ->
        :ok
    end
  end

  defp capture_known_calls(fun) do
    Process.put(:known_calls, [])

    HookRepo.set_hook(fn sql, params ->
      if String.contains?(sql, "v.ended_at >= $3"),
        do: Process.put(:known_calls, Process.get(:known_calls) ++ [params])
    end)

    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, HookRepo)

    try do
      fun.()
    after
      Application.put_env(:dawarich, :jobs_repo, previous)
    end

    Process.get(:known_calls)
  end

  defp fixed_args(uid, start_at, end_at) do
    %{
      "event_id" => Ecto.UUID.generate(),
      "user_id" => uid,
      "start_at" => start_at,
      "end_at" => end_at,
      "stepping" => "fixed",
      "time_zone" => "UTC",
      "plan_restricted" => false,
      "cursor" => start_at
    }
  end

  defp job_count,
    do: hd(hd(rows("SELECT count(*) FROM oban.oban_jobs WHERE worker = $1", [@worker])))

  defp notifications(uid) do
    for [kind, title, content] <-
          rows("SELECT kind, title, content FROM notifications WHERE user_id = $1 ORDER BY id", [
            uid
          ]),
        do: %{"kind" => kind, "title" => title, "content" => content}
  end

  defp local_epoch(iso, zone) do
    [[epoch]] =
      rows("SELECT extract(epoch FROM ($1::timestamp AT TIME ZONE $2))::bigint", [
        NaiveDateTime.from_iso8601!(iso),
        zone
      ])

    epoch
  end

  defp epoch(%NaiveDateTime{} = naive), do: NaiveDateTime.diff(naive, ~N[1970-01-01 00:00:00])
end
