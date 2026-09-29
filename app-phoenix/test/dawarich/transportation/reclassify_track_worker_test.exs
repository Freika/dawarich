defmodule Dawarich.Transportation.ReclassifyTrackWorkerTest do
  use Dawarich.TracksCase

  alias Dawarich.Transportation.ReclassifyTrackWorker

  defp run(args, opts \\ []), do: ReclassifyTrackWorker.run(ScratchRepo, oban(), args, opts)

  defp progress,
    do:
      rows(
        "SELECT payload FROM phoenix.rails_commands WHERE kind = 'transport_progress' ORDER BY id"
      )
      |> List.flatten()

  test "progress is written once per event id" do
    %{expected: expected} = TracksFixtures.load!(ScratchRepo, "transport_reclassify")
    known = identities()
    event_id = Ecto.UUID.generate()
    args = %{"track_id" => 1, "report_progress" => true, "user_id" => nil, "event_id" => event_id}

    assert run(args) == :ok
    assert run(args) == :ok

    assert progress() == [%{"user_id" => 1, "event_id" => event_id}]

    assert rows("SELECT dominant_mode FROM tracks WHERE id = 1") == [
             [hd(expected["tracks"])["dominant_mode"]]
           ]

    assert rows("SELECT count(*) FROM track_segments") == [[length(expected["track_segments"])]]
    assert events(known) == expected_events(expected)

    assert [
             %{
               "created" => [],
               "updated" => [],
               "destroyed" => [],
               "min_ts" => 1_796_108_400,
               "max_ts" => 1_796_108_730
             },
             _
           ] = tracks_changed()
  end

  test "a missing track and a final failure still report progress" do
    TracksFixtures.load!(ScratchRepo, "transport_reclassify")
    missing = Ecto.UUID.generate()
    orphan = Ecto.UUID.generate()
    failing = Ecto.UUID.generate()

    assert run(%{
             "track_id" => 424_242,
             "report_progress" => true,
             "user_id" => 1,
             "event_id" => missing
           }) == :ok

    assert run(%{
             "track_id" => 424_242,
             "report_progress" => true,
             "user_id" => nil,
             "event_id" => orphan
           }) == :ok

    args = %{"track_id" => 1, "report_progress" => true, "user_id" => 1, "event_id" => failing}
    raising = fn :reclassified -> raise "boom" end

    for attempt <- [1, 2] do
      assert_raise RuntimeError, "boom", fn ->
        run(args, attempt: attempt, max_attempts: 2, hook: raising)
      end
    end

    assert progress() == [
             %{"user_id" => 1, "event_id" => missing},
             %{"user_id" => 1, "event_id" => failing}
           ]

    assert tracks_changed() == []
  end

  test "no progress is reported unless asked" do
    TracksFixtures.load!(ScratchRepo, "transport_reclassify")

    assert run(%{
             "track_id" => 1,
             "report_progress" => false,
             "user_id" => 1,
             "event_id" => Ecto.UUID.generate()
           }) == :ok

    assert progress() == []
    assert rows("SELECT count(*) FROM phoenix.processed_commands") == [[0]]
  end

  test "decodes version 1 payloads exactly" do
    payload = %{"track_id" => 7, "report_progress" => true, "user_id" => nil}

    assert ReclassifyTrackWorker.args_from_command(1, payload) == {:ok, payload}

    assert ReclassifyTrackWorker.args_from_command(1, %{payload | "user_id" => 3}) ==
             {:ok, %{payload | "user_id" => 3}}

    for bad <- [
          Map.put(payload, "extra", 1),
          Map.delete(payload, "user_id"),
          %{payload | "track_id" => "7"},
          %{payload | "report_progress" => nil},
          %{payload | "user_id" => "3"}
        ],
        do: assert(ReclassifyTrackWorker.args_from_command(1, bad) == {:error, "invalid_payload"})

    assert ReclassifyTrackWorker.args_from_command(2, payload) == {:error, "unsupported_version"}
  end
end
