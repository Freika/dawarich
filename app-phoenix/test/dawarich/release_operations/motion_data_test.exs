defmodule Dawarich.ReleaseOperations.MotionDataTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.{ReleaseOperations, Wave6Fixtures}
  alias Dawarich.ReleaseOperations.{MotionData, MotionExtractor}

  @oban Dawarich.ReleaseOperations.MotionDataTest.Oban
  @old ~N[2020-01-01 00:00:00]

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban)
    %{user: Wave6Fixtures.user!()}
  end

  defp run(args) do
    ReleaseOperations.run(ScratchRepo, @oban, MotionData, %Oban.Job{
      args: args,
      attempt: 1,
      max_attempts: 10
    })
  end

  defp start(batch_size) do
    run(%{
      "version" => 1,
      "event_id" => Ecto.UUID.generate(),
      "cursor" => %{"after_id" => 0, "batch_size" => batch_size}
    })
  end

  defp drain!(seen \\ []) do
    case rows(
           "DELETE FROM oban.oban_jobs WHERE id = (SELECT min(id) FROM oban.oban_jobs) RETURNING args"
         ) do
      [] ->
        Enum.reverse(seen)

      [[args]] ->
        :ok = run(args)
        drain!([args["cursor"]["after_id"] | seen])
    end
  end

  defp point!(user, motion, raw),
    do:
      Wave6Fixtures.point!(user, %{
        "motion_data" => motion,
        "raw_data" => raw,
        "updated_at" => @old
      })

  defp state(id),
    do: hd(rows("SELECT motion_data, updated_at > $2 FROM points WHERE id = $1", [id, @old]))

  test "the extractor matches Rails for every fixture case" do
    for %{"raw_data" => raw, "expected" => expected} <-
          Wave6Fixtures.load!("extractors")["motion"] do
      assert MotionExtractor.from_raw_data(raw) == expected, inspect(raw)
    end

    assert MotionExtractor.from_raw_data(%{
             "properties" => %{"motion" => ["walking"]},
             "waypointPath" => "x"
           }) ==
             %{"motion" => ["walking"]}
  end

  test "a non-map truthy properties or waypointPath raises" do
    assert_raise ArgumentError, fn ->
      MotionExtractor.from_raw_data(%{"properties" => "walking"})
    end

    assert_raise ArgumentError, fn ->
      MotionExtractor.from_raw_data(%{"waypointPath" => ["WALK"]})
    end

    assert_raise ArgumentError, fn ->
      MotionExtractor.from_raw_data(%{"waypointPath" => false})
    end
  end

  test "backfills only empty motion with raw data and moves updated_at", %{user: user} do
    filled = point!(user, %{}, %{"activity" => "WALKING"})
    kept = point!(user, %{"m" => 1}, %{"activity" => "STILL"})
    bare = point!(user, %{}, %{})
    unknown = point!(user, %{}, %{"x" => 1})

    assert start(1_000) == :ok
    drain!()

    assert state(filled) == [%{"activity" => "WALKING"}, true]
    assert state(kept) == [%{"m" => 1}, false]
    assert state(bare) == [%{}, false]
    assert state(unknown) == [%{}, false]
  end

  test "the chain pages by id and completes on an empty page", %{user: user} do
    [_first, second, third] = for n <- 1..3, do: point!(user, %{}, %{"m" => n})

    assert start(2) == :ok
    assert drain!() == [second, third]

    assert rows("SELECT status FROM phoenix.release_operations") == [["completed"]]
    assert rows("SELECT count(*) FROM points WHERE motion_data = '{}'::jsonb") == [[0]]
  end

  test "backfilled floats are stored as Rails stores them: whole floats stay floats, no Jason scale",
       %{user: user} do
    whole = point!(user, %{}, %{})
    small = point!(user, %{}, %{})
    rows("UPDATE points SET raw_data = $2::text::jsonb WHERE id = $1", [whole, ~s({"m": 1000.0})])
    rows("UPDATE points SET raw_data = $2::text::jsonb WHERE id = $1", [small, ~s({"m": 1e-05})])

    assert start(1_000) == :ok
    drain!()

    assert rows("SELECT motion_data::text FROM points WHERE id = ANY($1) ORDER BY id", [
             [whole, small]
           ]) == [[~s({"m": 1000.0})], [~s({"m": 0.00001})]]
  end
end
