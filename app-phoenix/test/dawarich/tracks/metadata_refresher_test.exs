defmodule Dawarich.Tracks.MetadataRefresherTest do
  use Dawarich.TracksCase, async: true, group: :tracks_db

  import ExUnit.CaptureLog

  alias Dawarich.Tracks.MetadataRefresher

  test "an incomplete refresh logs the result with Ruby's key order" do
    user = user!()
    id = track!(user.id, "device-m", 1_790_200_000, 1_790_200_600)
    point!(user.id, 1_790_200_300, 12.3731, 51.3397, tracker_id: "device-m", track_id: id)

    {result, log} = with_log(fn -> MetadataRefresher.run(ScratchRepo, user) end)

    assert result == %{
             refreshed: 0,
             skipped: 1,
             reasons: [insufficient_points: 1],
             sample_ids: [id]
           }

    assert log =~
             "event=tracks.metadata_refresh_incomplete user_id=#{user.id} " <>
               ~s(result={"refreshed":0,"skipped":1,"reasons":{"insufficient_points":1},"sample_ids":[#{id}]})
  end
end
