defmodule Dawarich.ReleaseOperations.TimeAnchorTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.{ReleaseOperations, Wave6Fixtures}
  alias Dawarich.ReleaseOperations.TimeAnchor

  @oban Dawarich.ReleaseOperations.TimeAnchorTest.Oban
  @ts 1_577_836_800

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban)
    user = Wave6Fixtures.user!()
    %{user: user, track: Wave6Fixtures.track!(user)}
  end

  test "anchors index-only segments, drops unanchorable uncorrected ones and continues from the last id",
       %{user: user, track: track} do
    for {offset, lon} <- [{0, 12.3731}, {60, 12.3741}, {120, 12.3751}, {180, 12.3761}] do
      Wave6Fixtures.point!(user, %{
        "track_id" => track,
        "timestamp" => @ts + offset,
        "lonlat" => {:point, lon, 51.3397}
      })
    end

    anchorable = Wave6Fixtures.segment!(track, %{"start_index" => 0, "end_index" => 1})
    Wave6Fixtures.segment!(track, %{"start_index" => 5, "end_index" => 9})

    corrected =
      Wave6Fixtures.segment!(track, %{
        "start_index" => 6,
        "end_index" => 9,
        "corrected_at" => NaiveDateTime.utc_now()
      })

    {id, :ok} =
      run(%{"version" => 1, "event_id" => Ecto.UUID.generate(), "cursor" => %{"from_id" => 0}})

    assert segments() == [
             [anchorable, @ts, @ts + 60, "LINESTRING(12.3731 51.3397,12.3741 51.3397)"],
             [corrected, nil, nil, nil]
           ]

    assert [[successor]] = rows("SELECT args FROM oban.oban_jobs")

    assert successor == %{
             "version" => 1,
             "operation_id" => id,
             "cursor" => %{"from_id" => corrected}
           }

    assert run(successor) == {id, :ok}
    assert status(id) == "completed"
    assert length(rows("SELECT id FROM oban.oban_jobs")) == 1
  end

  test "a collision after duplicate removal falls back to per-row anchoring", %{
    user: user,
    track: track
  } do
    for {offset, lon} <- [{0, 12.3731}, {0, 12.3741}, {60, 12.3751}, {120, 12.3761}] do
      Wave6Fixtures.point!(user, %{
        "track_id" => track,
        "timestamp" => @ts + offset,
        "lonlat" => {:point, lon, 51.3397}
      })
    end

    anchored =
      Wave6Fixtures.segment!(track, %{
        "start_at" => DateTime.from_unix!(@ts),
        "end_at" => DateTime.from_unix!(@ts + 30)
      })

    Wave6Fixtures.segment!(track, %{"start_index" => 0, "end_index" => 1})

    corrected =
      Wave6Fixtures.segment!(track, %{
        "start_index" => 1,
        "end_index" => 2,
        "corrected_at" => NaiveDateTime.utc_now()
      })

    single = Wave6Fixtures.segment!(track, %{"start_index" => 3, "end_index" => 3})

    {_id, :ok} =
      run(%{"version" => 1, "event_id" => Ecto.UUID.generate(), "cursor" => %{"from_id" => 0}})

    assert segments() == [
             [anchored, @ts, @ts + 30, nil],
             [corrected, nil, nil, nil],
             [single, @ts + 120, @ts + 120, nil]
           ]
  end

  test "decodes version 1 payloads exactly" do
    assert TimeAnchor.args_from_command(1, %{"from_id" => 0}) ==
             {:ok, %{"version" => 1, "cursor" => %{"from_id" => 0}}}

    for invalid <- [%{}, %{"from_id" => "0"}, %{"from_id" => 0, "extra" => 1}] do
      assert TimeAnchor.args_from_command(1, invalid) == {:error, "invalid_payload"}
    end

    assert TimeAnchor.args_from_command(2, %{"from_id" => 0}) == {:error, "unsupported_version"}
  end

  defp run(args) do
    job = %Oban.Job{args: args, attempt: 1, max_attempts: 10}

    {args["event_id"] || args["operation_id"],
     ReleaseOperations.run(ScratchRepo, @oban, TimeAnchor, job)}
  end

  defp segments,
    do:
      rows("""
      SELECT id, extract(epoch FROM start_at)::bigint, extract(epoch FROM end_at)::bigint, ST_AsText(path)
      FROM track_segments ORDER BY id
      """)

  defp status(id) do
    [[status]] =
      rows("SELECT status FROM phoenix.release_operations WHERE id = $1", [Ecto.UUID.dump!(id)])

    status
  end
end
